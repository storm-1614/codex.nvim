local config = require("codex.config")
local util = require("codex.util")

local M = {}
local state = {
  buf = nil,
  win = nil,
  job = nil,
  cwd = nil,
  model = nil,
  previous_win = nil,
  starting = false,
}

local function job_is_running()
  return state.job and state.job > 0 and vim.fn.jobwait({ state.job }, 0)[1] == -1
end

local function close_window()
  if util.is_valid_win(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

local function cleanup_buffer()
  if util.is_valid_buf(state.buf) and not job_is_running() then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
end

local function apply_window_options(win, opts)
  for name, value in pairs(opts or {}) do
    pcall(vim.api.nvim_set_option_value, name, value, { win = win })
  end
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

local function terminal_exit(job, code, _)
  vim.schedule(function()
    -- Ignore an old process callback after the user has stopped it and
    -- launched a new terminal.
    if state.job ~= job then
      return
    end
    local exited_buf = state.buf
    state.job = nil
    state.starting = false
    if config.get().on_exit then
      pcall(config.get().on_exit, vim.deepcopy(state), code)
    end
    if config.get().auto_close then
      close_window()
      if util.is_valid_buf(exited_buf) then
        vim.api.nvim_buf_delete(exited_buf, { force = true })
      end
      state.buf = nil
    else
      if util.is_valid_buf(exited_buf) then
        vim.bo[exited_buf].modified = false
      end
    end
  end)
end

local function build_command(extra_args)
  local cfg = config.get()
  local command = util.command_list(cfg.terminal_cmd)
  if state.model and state.model ~= "" then
    vim.list_extend(command, { "--model", state.model })
  end
  vim.list_extend(command, extra_args or {})
  return command
end

function M.get_state()
  return state
end

function M.is_open()
  return util.is_valid_win(state.win) and util.is_valid_buf(state.buf)
end

function M.is_running()
  return job_is_running()
end

function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
    if config.get().enter_insert then
      vim.cmd("startinsert")
    end
    return true
  end
  return false
end

function M.open(extra_args)
  if M.is_open() and job_is_running() then
    M.focus()
    return true
  end

  if job_is_running() and util.is_valid_buf(state.buf) then
    -- `close()` hides the split but intentionally keeps the CLI alive. Reuse
    -- that terminal buffer instead of starting a second Codex process.
    state.win = create_window()
    vim.api.nvim_win_set_buf(state.win, state.buf)
    if config.get().enter_insert then
      vim.cmd("startinsert")
    end
    return true
  end

  if util.is_valid_buf(state.buf) and not job_is_running() then
    cleanup_buffer()
  end

  state.previous_win = vim.api.nvim_get_current_win()
  state.cwd = util.cwd(config.get())
  state.win = create_window()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.buf, "[Codex]")
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "codex_terminal"

  local term_opts = {
    cwd = state.cwd,
    on_exit = terminal_exit,
  }
  if config.get().env and next(config.get().env) ~= nil then
    term_opts.env = config.get().env
  end
  local job = vim.fn.termopen(build_command(extra_args), term_opts)
  if job <= 0 then
    close_window()
    vim.api.nvim_buf_delete(state.buf, { force = true })
    state.buf = nil
    state.job = nil
    util.notify("Unable to start Codex CLI; verify that terminal_cmd is executable: " .. vim.inspect(config.get().terminal_cmd), vim.log.levels.ERROR)
    return false
  end
  state.job = job
  state.starting = true
  vim.defer_fn(function()
    if state.job == job then
      state.starting = false
    end
  end, config.get().startup_delay_ms)

  if config.get().on_open then
    pcall(config.get().on_open, vim.deepcopy(state))
  end
  if config.get().enter_insert then
    vim.cmd("startinsert")
  end
  return true
end

function M.close()
  if not M.is_open() then
    return false
  end
  close_window()
  if config.get().on_close then
    pcall(config.get().on_close, vim.deepcopy(state))
  end
  return true
end

function M.stop()
  if state.job and state.job > 0 then
    vim.fn.jobstop(state.job)
    state.job = nil
  end
  state.starting = false
  close_window()
  cleanup_buffer()
  if config.get().on_close then
    pcall(config.get().on_close, vim.deepcopy(state))
  end
end

function M.toggle()
  if M.is_open() then
    return M.close()
  end
  return M.open()
end

function M.focus_toggle()
  if M.is_open() then
    if vim.api.nvim_get_current_win() == state.win then
      return M.close()
    end
    return M.focus()
  end
  return M.open()
end

local function paste_payload(text)
  -- Codex uses a terminal line editor. Bracketed paste keeps newlines inside a
  -- multi-line prompt from being interpreted as individual submit events.
  if text:find("\n", 1, true) then
    return "\27[200~" .. text .. "\27[201~"
  end
  return text
end

local function terminal_channel()
  if not util.is_valid_buf(state.buf) then
    return nil
  end

  -- Match claudecode.nvim: prefer the terminal buffer's job id and use the
  -- buffer channel as a fallback for recovered terminal buffers.
  local channel = vim.b[state.buf] and vim.b[state.buf].terminal_job_id
  if not channel or channel == 0 then
    channel = vim.bo[state.buf].channel
  end
  if (not channel or channel == 0) and state.job and state.job > 0 then
    channel = state.job
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

local function send_payload(text, opts)
  local channel = terminal_channel()
  if not channel or channel == 0 then
    util.notify("Unable to send text to Codex CLI: terminal channel is unavailable", vim.log.levels.ERROR)
    return false
  end

  local payload = paste_payload(text)
  if opts.submit ~= false then
    -- Keep the submit byte in the same write, after the closing paste marker.
    -- This prevents a separate delayed event from unexpectedly submitting a
    -- visual selection.
    payload = payload .. "\r"
  end
  if not send_channel(channel, payload) then
    return false
  end

  if opts.focus ~= false and config.get().focus_after_send then
    M.focus()
  end
  return true
end

function M.send(text, opts)
  opts = opts or {}
  text = util.escape_prompt(text or "")
  if text == "" then
    return false
  end

  local was_running = M.is_running()
  local cold_start = not was_running or state.starting
  local needs_open = not M.is_open() or not was_running
  if needs_open then
    -- Selection insertion must also work before Codex has been opened.
    if not M.open() then
      return false
    end
  end

  if cold_start then
    local job = state.job
    -- A newly spawned Codex TUI can clear or redraw its input area while it is
    -- starting. Defer the first write until the initial prompt is available.
    -- This is the cold-start path only; an already running session remains
    -- synchronous.
    vim.defer_fn(function()
      if state.job == job and job_is_running() then
        state.starting = false
        send_payload(text, opts)
      end
    end, config.get().startup_delay_ms)
    return true
  end

  return send_payload(text, opts)
end

function M.send_selection(selection)
  selection = selection or util.visual_selection()
  if not selection or not selection.lines or #selection.lines == 0 then
    util.notify("Select text to insert into Codex first", vim.log.levels.WARN)
    return false
  end
  -- Insert exactly what was selected. Do not add an instruction, file path,
  -- line range, or code fences; the Codex prompt should contain the user's
  -- selected text and nothing else.
  return M.send(selection.text or table.concat(selection.lines, "\n"), { submit = false })
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
