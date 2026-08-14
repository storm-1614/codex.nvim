local config = require("codex.config")
local terminal = require("codex.terminal")
local util = require("codex.util")

local M = {
  terminal = terminal,
}

local function selection_or_nil()
  return util.visual_selection()
end

function M.setup(opts)
  config.setup(opts)
  if config.get().keymaps.enabled then
    M.setup_keymaps()
  end
end

function M.setup_keymaps()
  local km = config.get().keymaps
  local map_opts = { silent = true, desc = "Codex" }
  vim.keymap.set("n", km.toggle, terminal.toggle, vim.tbl_extend("force", map_opts, { desc = "Codex: toggle" }))
  vim.keymap.set("n", km.focus, terminal.focus_toggle, vim.tbl_extend("force", map_opts, { desc = "Codex: focus" }))
  vim.keymap.set("n", km.resume, M.resume, vim.tbl_extend("force", map_opts, { desc = "Codex: resume" }))
  vim.keymap.set("n", km.continue_session, M.continue_session, vim.tbl_extend("force", map_opts, { desc = "Codex: continue" }))
  vim.keymap.set({ "n", "v" }, km.add_current, function()
    if vim.fn.mode():match("^[vV\22]") then
      return terminal.send_selection(selection_or_nil())
    end
    return terminal.send_current_file()
  end, vim.tbl_extend("force", map_opts, { desc = "Codex: insert selection/file" }))
  vim.keymap.set("v", km.send, function()
    return terminal.send_selection(selection_or_nil())
  end, vim.tbl_extend("force", map_opts, { desc = "Codex: insert selection" }))
  vim.keymap.set("n", km.tree_add, M.tree_add, vim.tbl_extend("force", map_opts, { desc = "Codex: add file" }))
  vim.keymap.set("n", km.diff_accept, M.diff_accept, vim.tbl_extend("force", map_opts, { desc = "Codex: accept diff" }))
  vim.keymap.set("n", km.diff_deny, M.diff_deny, vim.tbl_extend("force", map_opts, { desc = "Codex: deny diff" }))
  vim.keymap.set("n", km.diff_accept_all, M.diff_accept_all, vim.tbl_extend("force", map_opts, { desc = "Codex: accept all diffs" }))
  vim.keymap.set("n", km.diff_deny_all, M.diff_deny_all, vim.tbl_extend("force", map_opts, { desc = "Codex: deny all diffs" }))
  vim.keymap.set("n", km.select_model, M.select_model, vim.tbl_extend("force", map_opts, { desc = "Codex: select model" }))
  vim.keymap.set("n", km.stop, terminal.stop, vim.tbl_extend("force", map_opts, { desc = "Codex: stop" }))
end

function M.resume()
  if terminal.is_running() then
    terminal.stop()
  end
  return terminal.open({ "resume", "--last" })
end

function M.continue_session()
  if terminal.is_running() then
    terminal.stop()
  end
  return terminal.open({ "resume", "--last" })
end

function M.open(args)
  args = args or {}
  if #args > 0 then
    if not terminal.open() then
      return false
    end
    return terminal.send(table.concat(args, " "))
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

function M.add_current(file, start_line, end_line)
  if file and file ~= "" then
    local location = vim.fn.fnamemodify(vim.fn.expand(file), ":p")
    local suffix = ""
    if start_line and start_line > 0 then
      suffix = string.format(" (lines %d-%d)", start_line, end_line or start_line)
    end
    return terminal.send("Please inspect and process this file" .. suffix .. ":" .. location)
  end
  return terminal.send_current_file()
end

function M.tree_add(file)
  return M.add_current(file)
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

function M.status()
  local state = terminal.get_state()
  local status = terminal.is_running() and "running" or "stopped"
  util.notify(string.format("Codex: %s%s", status, state.cwd and (" (cwd: " .. state.cwd .. ")") or ""))
end

return M
