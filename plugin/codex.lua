if vim.g.loaded_codex_nvim then
  return
end
vim.g.loaded_codex_nvim = 1

local codex = require("codex")

local function command(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts or {})
end

command("Codex", function(args)
  codex.open(args.fargs)
end, { nargs = "*", desc = "Open Codex CLI and optionally send a prompt" })
command("CodexOpen", codex.open, { desc = "Open Codex CLI" })
command("CodexStart", codex.start, { desc = "Start Codex CLI" })
command("CodexResume", codex.resume, { desc = "Open the Codex session picker" })
command("CodexContinue", codex.continue_session, { desc = "Continue the most recent Codex session" })
command("CodexToggle", codex.toggle, { desc = "Toggle Codex side panel" })
command("CodexFocus", codex.focus, { desc = "Focus Codex side panel" })
command("CodexClose", codex.close, { desc = "Close Codex side panel" })
command("CodexStop", codex.stop, { desc = "Stop Codex CLI" })
command("CodexStatus", codex.status, { desc = "Show Codex status" })
command("CodexAdd", function(args)
  local file = args.fargs[1]
  -- `line1` and `line2` default to the current line even when no Ex range was
  -- supplied. Only attach a line range when the caller explicitly supplied it.
  local start_line = args.range > 0 and args.line1 or nil
  local end_line = args.range > 0 and args.line2 or nil
  codex.add_current(file, start_line, end_line)
end, { nargs = "*", range = true, desc = "Send current file/selection to Codex" })
command("CodexTreeAdd", function(args)
  codex.tree_add(args.fargs[1])
end, { nargs = "?", desc = "Send a file from a tree to Codex" })
local function send_text_command(args)
  codex.send(table.concat(args.fargs, " "), { submit = not args.bang })
end
command("CodexSend", send_text_command, { nargs = "+", bang = true, desc = "Send a prompt to Codex" })
command("CodexSendText", send_text_command, { nargs = "+", bang = true, desc = "Send text to Codex" })
command("CodexDiffAccept", codex.diff_accept, { desc = "Accept current Codex diff" })
command("CodexDiffDeny", codex.diff_deny, { desc = "Deny current Codex diff" })
command("CodexDiffAcceptAll", codex.diff_accept_all, { desc = "Accept all Codex diffs" })
command("CodexDiffDenyAll", codex.diff_deny_all, { desc = "Deny all Codex diffs" })
command("CodexCloseAllDiffs", codex.diff_deny_all, { desc = "Close all Codex diffs" })
command("CodexSelectModel", codex.select_model, { desc = "Select Codex model" })
command("CodexSelectBuffer", codex.select_buffer, { desc = "Insert a Neovim buffer into Codex" })
