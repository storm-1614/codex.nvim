local config = require("codex.config")
local terminal = require("codex.terminal")
local util = require("codex.util")

local M = {
  terminal = terminal,
}

local installed_keymaps = {}

local function selection_or_nil()
  return util.visual_selection()
end

function M.setup(opts)
  config.setup(opts)
  M.clear_keymaps()
  if config.get().keymaps.enabled then
    M.setup_keymaps()
  end
end

function M.clear_keymaps()
  for _, mapping in ipairs(installed_keymaps) do
    pcall(vim.keymap.del, mapping.mode, mapping.lhs)
  end
  installed_keymaps = {}
end

function M.setup_keymaps()
  M.clear_keymaps()
  local km = config.get().keymaps
  local map_opts = { silent = true, desc = "Codex" }
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", map_opts, { desc = desc }))
    if type(mode) == "table" then
      for _, item in ipairs(mode) do
        installed_keymaps[#installed_keymaps + 1] = { mode = item, lhs = lhs }
      end
    else
      installed_keymaps[#installed_keymaps + 1] = { mode = mode, lhs = lhs }
    end
  end

  map("n", km.toggle, terminal.toggle, "Codex: toggle")
  map("n", km.focus, terminal.focus_toggle, "Codex: focus")
  map("n", km.resume, M.resume, "Codex: resume")
  map("n", km.continue_session, M.continue_session, "Codex: continue")
  map({ "n", "v" }, km.add_current, function()
    if vim.fn.mode():match("^[vV\22]") then
      return terminal.send_selection(selection_or_nil())
    end
    return terminal.send_current_file()
  end, "Codex: insert file/selection reference")
  map("v", km.send, function()
    return terminal.send_selection(selection_or_nil())
  end, "Codex: insert selection reference")
  map("n", km.tree_add, M.tree_add, "Codex: add file")
  map("n", km.diff_accept, M.diff_accept, "Codex: accept diff")
  map("n", km.diff_deny, M.diff_deny, "Codex: deny diff")
  map("n", km.diff_accept_all, M.diff_accept_all, "Codex: accept all diffs")
  map("n", km.diff_deny_all, M.diff_deny_all, "Codex: deny all diffs")
  map("n", km.select_model, M.select_model, "Codex: select model")
  map("n", km.select_buffer, M.select_buffer, "Codex: insert buffer content")
  map("n", km.diagnostics, M.diagnostics, "Codex: diagnose current buffer")
  map("n", km.review, M.review, "Codex: review workspace changes")
  map("n", km.health, M.health, "Codex: health check")
  map("n", km.stop, terminal.stop, "Codex: stop")
end

function M.resume()
  if terminal.is_running() then
    terminal.stop()
  end
  -- `codex resume` opens Codex's built-in session picker.
  return terminal.open({ "resume" })
end

function M.continue_session()
  if terminal.is_running() then
    terminal.stop()
  end
  -- `--last` deliberately skips the picker and resumes the latest session.
  return terminal.open({ "resume", "--last" })
end

function M.open(args)
  args = args or {}
  if #args > 0 then
    local prompt = table.concat(args, " ")
    if not terminal.is_running() then
      -- The CLI supports an initial prompt argument; use it on cold starts so
      -- trust/setup gates cannot consume a prompt sent into the PTY too early.
      return terminal.open({ "--", prompt })
    end
    if not terminal.open() then
      return false
    end
    return terminal.send(prompt)
  end
  return terminal.open()
end

function M.focus()
  return terminal.focus_toggle()
end

function M.toggle()
  return terminal.toggle()
end

function M.close()
  return terminal.close()
end

function M.start()
  return terminal.open()
end

function M.stop()
  return terminal.stop()
end

function M.send(text, opts)
  return terminal.send(text, opts)
end

function M.send_selection()
  return terminal.send_selection(selection_or_nil())
end

function M.diagnostics(opts)
  opts = opts or {}
  local bufnr = opts.all and nil or vim.api.nvim_get_current_buf()
  local prompt, error_message = util.diagnostics_prompt(vim.diagnostic.get(bufnr))
  if not prompt then
    util.notify(error_message, vim.log.levels.INFO)
    return false
  end
  return terminal.send(prompt)
end

function M.quickfix()
  local list = vim.fn.getqflist({ items = 1 })
  local prompt, error_message = util.quickfix_prompt(list.items)
  if not prompt then
    util.notify(error_message, vim.log.levels.INFO)
    return false
  end
  return terminal.send(prompt)
end

function M.review()
  return terminal.send(
    "Review the current uncommitted workspace changes. Inspect the working tree and relevant diff yourself. "
      .. "Do not modify files. Report only actionable findings, ordered by severity, with file and line references; "
      .. "if there are no findings, say so briefly."
  )
end

local function terminal_command_status()
  local command = util.command_list(config.get().terminal_cmd)
  local executable = command[1]
  local available = vim.fn.executable(executable) == 1
  local path = available and vim.fn.exepath(executable) or ""
  return {
    command = table.concat(command, " "),
    executable = executable,
    path = path ~= "" and path or executable,
    available = available,
  }
end

local function working_directory_status()
  local cwd = util.cwd(config.get())
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(cwd)
  return {
    path = cwd,
    available = stat ~= nil and stat.type == "directory",
  }
end

-- Return a structured, side-effect-free status report for the current project.
function M.health_report()
  local cli = terminal_command_status()
  local cwd = working_directory_status()
  local session = terminal.peek_state()
  local running = terminal.is_running()
  local open = terminal.is_open()
  return {
    ok = cli.available and cwd.available,
    cli = cli,
    cwd = cwd,
    session = {
      started = session ~= nil,
      running = running,
      open = open,
    },
  }
end

function M.health()
  local report = M.health_report()
  local cli_mark = report.cli.available and "✓" or "✗"
  local cwd_mark = report.cwd.available and "✓" or "✗"
  local session_status
  if report.session.running then
    session_status = report.session.open and "运行中，侧栏已打开" or "运行中，侧栏已隐藏"
  elseif report.session.started then
    session_status = "已停止"
  else
    session_status = "尚未为当前项目启动"
  end

  local lines = {
    "Codex 健康检查",
    string.format("%s CLI: %s (%s)", cli_mark, report.cli.command, report.cli.path),
    string.format("%s 工作目录: %s", cwd_mark, report.cwd.path),
    "• 当前会话: " .. session_status,
    "• 登录状态: 为避免读取凭据，本检查不探测；首次启动时由 Codex CLI 确认。",
  }
  util.notify(table.concat(lines, "\n"), report.ok and vim.log.levels.INFO or vim.log.levels.WARN)
  return report.ok, report
end

function M.add_current(file, start_line, end_line)
  local target = file
  if not target or target == "" then
    target = util.current_file()
  end
  if not target then
    util.notify("The current buffer has no file name", vim.log.levels.WARN)
    return false
  end

  local location = vim.fn.fnamemodify(vim.fn.expand(target), ":p")
  local suffix = ""
  if start_line and start_line > 0 then
    suffix = string.format(" (lines %d-%d)", start_line, end_line or start_line)
  end
  return terminal.send("Please inspect and process this file" .. suffix .. ": " .. location)
end

function M.tree_add(file)
  local target = file
  if not target or target == "" then
    target = util.current_file()
  end
  if not target then
    util.notify("The current buffer has no file name", vim.log.levels.WARN)
    return false
  end

  local location = vim.fn.fnamemodify(vim.fn.expand(target), ":p")
  return terminal.send("Please inspect and process this file: " .. location, { submit = false })
end

local function diff_notice(action)
  util.notify(string.format(
    "Codex CLI applies changes directly in the workspace and does not expose an IDE diff protocol; %s was skipped.",
    action
  ), vim.log.levels.INFO)
end

-- Keep the command/keymap surface compatible with claudecode.nvim. Codex CLI
-- does not expose Claude's IDE diff protocol, so these are safe no-op actions.
function M.diff_accept()
  diff_notice("Accept current diff")
end

function M.diff_deny()
  diff_notice("Deny current diff")
end

function M.diff_accept_all()
  diff_notice("Accept all diffs")
end

function M.diff_deny_all()
  diff_notice("Deny all diffs")
end

function M.select_model()
  local models = config.get().models
  local function apply(model)
    if not model or model == "" then
      return
    end
    terminal.get_state().model = model
    util.notify("Codex model: " .. model)
    if terminal.is_running() then
      util.notify("The model will take effect the next time Codex starts", vim.log.levels.INFO)
    end
  end

  if #models > 0 then
    vim.ui.select(models, { prompt = "Select a Codex model" }, apply)
  else
    vim.ui.input({ prompt = "Codex model: ", default = terminal.get_state().model or "" }, apply)
  end
end

local function buffer_items()
  local items = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr)
        and vim.api.nvim_buf_is_loaded(bufnr)
        and vim.fn.buflisted(bufnr) == 1
        and vim.bo[bufnr].buftype ~= "terminal" then
      local name = vim.api.nvim_buf_get_name(bufnr)
      items[#items + 1] = {
        bufnr = bufnr,
        name = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:."),
      }
    end
  end
  return items
end

function M.send_buffer(bufnr)
  if type(bufnr) ~= "number"
      or not vim.api.nvim_buf_is_valid(bufnr)
      or not vim.api.nvim_buf_is_loaded(bufnr) then
    util.notify("The selected buffer is no longer available", vim.log.levels.WARN)
    return false
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  if content == "" then
    util.notify("The selected buffer is empty", vim.log.levels.WARN)
    return false
  end

  -- Leave the content in Codex's input box so the user can add instructions
  -- or review it before submitting.
  return terminal.send(content, { submit = false })
end

function M.select_buffer()
  local items = buffer_items()
  if #items == 0 then
    util.notify("No listed Neovim buffers are available", vim.log.levels.WARN)
    return false
  end

  vim.ui.select(items, {
    prompt = "Select a buffer to insert into Codex",
    format_item = function(item)
      return string.format("%d: %s", item.bufnr, item.name)
    end,
  }, function(item)
    if item then
      M.send_buffer(item.bufnr)
    end
  end)
  return true
end

function M.status()
  local state = terminal.get_state()
  local status = terminal.is_running() and "running" or "stopped"
  util.notify(string.format("Codex: %s%s", status, state.cwd and (" (cwd: " .. state.cwd .. ")") or ""))
end

return M
