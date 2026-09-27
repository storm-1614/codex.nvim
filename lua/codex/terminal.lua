local config = require("codex.config")
local util = require("codex.util")

local M = {}

-- A terminal process belongs to the project it was started for. Keeping this
-- state per cwd prevents a prompt from project B being sent to a live Codex
-- process whose workspace is project A.
local sessions = {}
local state = nil

local function new_state(key, cwd)
  return {
    key = key,
    buf = nil,
    win = nil,
    job = nil,
    cwd = cwd,
    model = nil,
    previous_win = nil,
    starting = false,
    pending_sends = {},
  }
end

local function session_context()
  local buf = vim.api.nvim_get_current_buf()
  local key = vim.b[buf].codex_session_key
  if key and sessions[key] then
    return key, sessions[key].cwd
  end

  local cwd = util.cwd(config.get())
  return vim.fn.fnamemodify(cwd, ":p"), cwd
end

local function select_session(create)
  local key, cwd = session_context()
  local session = sessions[key]
  if not session and create then
    session = new_state(key, cwd)
    sessions[key] = session
  end
  if session then
    state = session
  end
  return session
end

local function job_is_running(session)
  session = session or state
  return session and session.job and session.job > 0 and vim.fn.jobwait({ session.job }, 0)[1] == -1
end

local function is_open(session)
  return session and util.is_valid_win(session.win) and util.is_valid_buf(session.buf)
end

local function restore_previous_window(session, was_current)
  local previous_win = session.previous_win
  session.previous_win = nil
  if was_current and util.is_valid_win(previous_win) then
    pcall(vim.api.nvim_set_current_win, previous_win)
  end
end

local function close_window(session, restore_focus)
  if not session then
    return
  end

  local was_current = util.is_valid_win(session.win) and vim.api.nvim_get_current_win() == session.win
  if util.is_valid_win(session.win) then
    vim.api.nvim_win_close(session.win, true)
  end
  session.win = nil
  if restore_focus then
    restore_previous_window(session, was_current)
  end
end

local function cleanup_buffer(session)
  if session and util.is_valid_buf(session.buf) and not job_is_running(session) then
    vim.api.nvim_buf_delete(session.buf, { force = true })
  end
  if session then
    session.buf = nil
  end
end

local function apply_window_options(win, opts)
  for name, value in pairs(opts or {}) do
    pcall(vim.api.nvim_set_option_value, name, value, { win = win })
  end
end

local function clear_pending_sends(session)
  session.pending_sends = {}
end

local send_payload

local function flush_pending_sends(session, job)
  if session.job ~= job or not job_is_running(session) then
    clear_pending_sends(session)
    return
  end

  local pending = session.pending_sends
  clear_pending_sends(session)
  for _, request in ipairs(pending) do
    if session.job ~= job or not job_is_running(session) then
      break
    end
    send_payload(session, request.text, request.opts)
  end
end

-- TUI startup (including trust/login screens) may discard early stdin. A
-- running PTY or EnableBracketedPaste alone does not mean the composer exists.
local function observe_startup(session, job, data)
  local startup = session.startup
  if session.job ~= job or not session.starting or not startup then
    return
  end
  local output = startup.tail .. table.concat(data, "\n")
  for parameters, action in output:gmatch("\27%[%?([%d;]+)([hl])") do
    for mode in parameters:gmatch("%d+") do
      if mode == "2004" then
        startup.paste = action == "h"
      elseif mode == "25" then
        startup.cursor = action == "h"
      end
    end
  end
  -- Mode sequences can be split across stdout callbacks.
  startup.tail = output:sub(-32)
end

local function composer_visible(session)
  local startup = session.startup
  if not startup or not startup.paste or not startup.cursor or not util.is_valid_buf(session.buf) then
    return false
  end
  local height = util.is_valid_win(session.win) and vim.api.nvim_win_get_height(session.win) or vim.o.lines
  local count = vim.api.nvim_buf_line_count(session.buf)
  local lines = vim.api.nvim_buf_get_lines(session.buf, math.max(0, count - height), count, false)
  for _, line in ipairs(lines) do
    -- Codex also uses this arrow for numbered menu choices. Those are not an
    -- editable prompt, even if an older cursor-show sequence is still visible.
    if line:match("^%s*›") and not line:match("^%s*›%s*%d+%.") then
      return true
    end
  end
  return false
end

local function wait_for_composer(session, job)
  local startup = session.startup
  if session.job ~= job or not session.starting or not startup or not job_is_running(session) then
    return
  end
  local now = (vim.uv or vim.loop).hrtime() / 1e6
  if composer_visible(session) then
    startup.ready_since = startup.ready_since or now
    if now - startup.ready_since >= config.get().startup_delay_ms then
      session.starting = false
      session.startup = nil
      flush_pending_sends(session, job)
      return
    end
  else
    startup.ready_since = nil
  end
  local overdue = now - startup.started_at >= 10000
  if overdue and not startup.warned and #session.pending_sends > 0 then
    startup.warned = true
    util.notify("Codex is not ready for input yet. Complete any startup dialog; queued text is retained.", vim.log.levels.WARN)
  end
  vim.defer_fn(function()
    wait_for_composer(session, job)
  end, overdue and 250 or 50)
end

local function create_window()
  local side = config.get().split_side
  if side == "left" then
    vim.cmd("topleft vertical new")
  else
    vim.cmd("botright vertical new")
  end
  local win = vim.api.nvim_get_current_win()
  local width = math.max(1, math.floor(vim.o.columns * config.get().split_width_percentage))
  pcall(vim.api.nvim_win_set_width, win, width)
  apply_window_options(win, config.get().terminal_win_opts)
  return win
end

local function terminal_exit(session, job, code, _)
  vim.schedule(function()
    -- Ignore an old process callback after this project's terminal has been
    -- stopped and started again.
    if session.job ~= job then
      return
    end

    local exited_buf = session.buf
    session.job = nil
    session.starting = false
    session.startup = nil
    clear_pending_sends(session)
    if config.get().on_exit then
      pcall(config.get().on_exit, vim.deepcopy(session), code)
    end
    if config.get().auto_close then
      close_window(session, true)
      if util.is_valid_buf(exited_buf) then
        vim.api.nvim_buf_delete(exited_buf, { force = true })
      end
      session.buf = nil
    elseif util.is_valid_buf(exited_buf) then
      vim.bo[exited_buf].modified = false
    end
  end)
end

local function build_command(session, extra_args)
  local cfg = config.get()
  local command = util.command_list(cfg.terminal_cmd)
  if session.model and session.model ~= "" then
    vim.list_extend(command, { "--model", session.model })
  end
  vim.list_extend(command, extra_args or {})
  return command
end

local function focus_session(session)
  if is_open(session) then
    vim.api.nvim_set_current_win(session.win)
    if config.get().enter_insert then
      vim.cmd("startinsert")
    end
    return true
  end
  return false
end

function M.get_state()
  return select_session(true)
end

-- Unlike get_state(), this does not allocate state for a project that has
-- never opened a Codex terminal. It is useful for read-only status checks.
function M.peek_state()
  return select_session(false)
end

function M.get_sessions()
  return sessions
end

function M.is_open()
  return is_open(select_session(false))
end

function M.is_running()
  return job_is_running(select_session(false))
end

function M.focus()
  return focus_session(select_session(false))
end

function M.open(extra_args)
  local session = select_session(true)
  if is_open(session) and job_is_running(session) then
    focus_session(session)
    return true
  end

  if job_is_running(session) and util.is_valid_buf(session.buf) then
    -- `close()` hides the split but intentionally keeps the CLI alive. Reuse
    -- that terminal buffer instead of starting a second Codex process.
    session.previous_win = vim.api.nvim_get_current_win()
    session.win = create_window()
    vim.api.nvim_win_set_buf(session.win, session.buf)
    if config.get().enter_insert then
      vim.cmd("startinsert")
    end
    return true
  end

  if util.is_valid_buf(session.buf) and not job_is_running(session) then
    cleanup_buffer(session)
  end

  session.cwd = util.cwd(config.get())
  session.previous_win = vim.api.nvim_get_current_win()
  clear_pending_sends(session)
  session.win = create_window()
  session.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(session.buf, "[Codex: " .. session.cwd .. "]")
  vim.b[session.buf].codex_session_key = session.key
  vim.api.nvim_win_set_buf(session.win, session.buf)
  vim.bo[session.buf].bufhidden = "hide"
  vim.bo[session.buf].swapfile = false
  vim.bo[session.buf].filetype = "codex_terminal"

  local term_opts = {
    cwd = session.cwd,
    on_stdout = function(job, data)
      observe_startup(session, job, data)
    end,
    on_exit = function(job, code, event)
      terminal_exit(session, job, code, event)
    end,
  }
  if config.get().env and next(config.get().env) ~= nil then
    term_opts.env = config.get().env
  end
  local job = vim.fn.termopen(build_command(session, extra_args), term_opts)
  if job <= 0 then
    close_window(session, true)
    vim.api.nvim_buf_delete(session.buf, { force = true })
    session.buf = nil
    session.job = nil
    util.notify("Unable to start Codex CLI; verify that terminal_cmd is executable: " .. vim.inspect(config.get().terminal_cmd), vim.log.levels.ERROR)
    return false
  end

  session.job = job
  session.starting = true
  session.startup = {
    tail = "", paste = false, cursor = false,
    started_at = (vim.uv or vim.loop).hrtime() / 1e6,
  }
  vim.defer_fn(function()
    wait_for_composer(session, job)
  end, 50)

  if config.get().on_open then
    pcall(config.get().on_open, vim.deepcopy(session))
  end
  if config.get().enter_insert then
    vim.cmd("startinsert")
  end
  return true
end

function M.close()
  local session = select_session(false)
  if not is_open(session) then
    return false
  end
  close_window(session, true)
  if config.get().on_close then
    pcall(config.get().on_close, vim.deepcopy(session))
  end
  return true
end

function M.stop()
  local session = select_session(false)
  if not session then
    return false
  end
  if session.job and session.job > 0 then
    vim.fn.jobstop(session.job)
    session.job = nil
  end
  session.starting = false
  session.startup = nil
  clear_pending_sends(session)
  close_window(session, true)
  cleanup_buffer(session)
  if config.get().on_close then
    pcall(config.get().on_close, vim.deepcopy(session))
  end
  return true
end

function M.toggle()
  local session = select_session(false)
  if is_open(session) then
    return M.close()
  end
  return M.open()
end

function M.focus_toggle()
  local session = select_session(false)
  if is_open(session) then
    if vim.api.nvim_get_current_win() == session.win then
      return M.close()
    end
    return focus_session(session)
  end
  return M.open()
end

local function paste_payload(text)
  -- Codex uses a terminal line editor. Bracketed paste keeps newlines and tabs
  -- inside pasted source from being interpreted as individual UI key presses.
  if text:find("[\n\t]") then
    return "\27[200~" .. text .. "\27[201~"
  end
  return text
end

local function terminal_channel(session)
  if not util.is_valid_buf(session.buf) then
    return nil
  end

  -- Match claudecode.nvim: prefer the terminal buffer's job id and use the
  -- buffer channel as a fallback for recovered terminal buffers.
  local channel = vim.b[session.buf] and vim.b[session.buf].terminal_job_id
  if not channel or channel == 0 then
    channel = vim.bo[session.buf].channel
  end
  if (not channel or channel == 0) and session.job and session.job > 0 then
    channel = session.job
  end
  return channel
end

local function send_channel(channel, payload)
  local ok, written = pcall(vim.fn.chansend, channel, payload)
  if not ok or not written or written <= 0 then
    util.notify("Unable to send text to Codex CLI: terminal channel is closed", vim.log.levels.ERROR)
    return false
  end
  return true
end

send_payload = function(session, text, opts)
  local channel = terminal_channel(session)
  if not channel or channel == 0 then
    util.notify("Unable to send text to Codex CLI: terminal channel is unavailable", vim.log.levels.ERROR)
    return false
  end

  local payload = paste_payload(text)
  if not send_channel(channel, payload) then
    return false
  end

  if opts.submit ~= false then
    -- Codex handles bracketed paste asynchronously. Sending Enter in the same
    -- PTY write can make the TUI consume it as part of the paste, leaving the
    -- composer stuck in its pasted-content state. Submit as a separate key
    -- event after the paste has had a chance to be processed.
    local job = session.job
    vim.defer_fn(function()
      if session.job == job and job_is_running(session) then
        send_channel(channel, "\r")
      end
    end, 50)
  end

  if opts.focus ~= false and config.get().focus_after_send then
    focus_session(session)
  end
  return true
end

function M.send(text, opts)
  opts = opts or {}
  text = util.escape_prompt(text or "")
  if text == "" then
    return false
  end

  local session = select_session(true)
  local was_running = job_is_running(session)
  local needs_open = not is_open(session) or not was_running
  if needs_open then
    if not was_running and opts.submit ~= false then
      -- Codex accepts an initial prompt as a positional CLI argument. Using
      -- that path avoids racing the TUI's startup gates with PTY input.
      return M.open({ "--", text })
    end
    -- Selection insertion must also work before Codex has been opened.
    if not M.open() then
      return false
    end
  end

  if session.starting then
    -- A newly spawned TUI may redraw its input area while starting. Keep all
    -- requests in one FIFO queue so a second send during this interval does
    -- not incur another full delay or overtake the first prompt.
    session.pending_sends[#session.pending_sends + 1] = { text = text, opts = opts }
    return true
  end

  return send_payload(session, text, opts)
end

function M.send_selection(selection)
  local prompt, error_message = util.selection_prompt(selection)
  if not prompt then
    util.notify(error_message, vim.log.levels.WARN)
    return false
  end
  return M.send(prompt, { submit = false })
end

function M.send_current_file()
  local file = util.current_file()
  if not file then
    util.notify("The current buffer has no file name", vim.log.levels.WARN)
    return false
  end
  return M.send("Please inspect and process this file: " .. file)
end

return M
