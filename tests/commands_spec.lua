vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local codex = require("codex")
local terminal = require("codex.terminal")
local util = require("codex.util")

local function assert_equal(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)))
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
vim.api.nvim_buf_set_name(0, "/tmp/codex-command-spec.lua")

local sent = {}
local original_send = terminal.send
terminal.send = function(text, opts)
  sent[#sent + 1] = { text = text, opts = opts }
  return true
end

dofile("plugin/codex.lua")
vim.cmd("1,2CodexAdd")
assert_equal(sent[1], {
  text = "Please inspect and process this file (lines 1-2): /tmp/codex-command-spec.lua",
  opts = nil,
}, "a ranged :CodexAdd must preserve the current-file range")

vim.cmd("CodexAdd")
assert_equal(sent[2], {
  text = "Please inspect and process this file: /tmp/codex-command-spec.lua",
  opts = nil,
}, "an unranged :CodexAdd must send the whole current file")

local namespace = vim.api.nvim_create_namespace("codex-command-spec")
vim.diagnostic.set(namespace, 0, {
  { lnum = 1, col = 2, severity = vim.diagnostic.severity.ERROR, source = "test", message = "bad value" },
})
vim.cmd("CodexDiagnostics")
assert_equal(sent[3], {
  text = "Please diagnose these Neovim diagnostics. Inspect the relevant source before proposing a fix. Do not modify files yet.\n\nDiagnostics:\n- ERROR /tmp/codex-command-spec.lua:2:3 [test]: bad value",
  opts = nil,
}, ":CodexDiagnostics must send current-buffer diagnostics")

vim.fn.setqflist({ { filename = "/tmp/codex-command-spec.lua", lnum = 3, col = 1, type = "W", text = "unused value" } })
vim.cmd("CodexQuickfix")
assert_equal(sent[4], {
  text = "Please diagnose these Neovim diagnostics. Inspect the relevant source before proposing a fix. Do not modify files yet.\n\nDiagnostics:\n- WARN /tmp/codex-command-spec.lua:3:1: unused value",
  opts = nil,
}, ":CodexQuickfix must send the current quickfix list")

vim.cmd("CodexReview")
assert_equal(sent[5], {
  text = "Review the current uncommitted workspace changes. Inspect the working tree and relevant diff yourself. Do not modify files. Report only actionable findings, ordered by severity, with file and line references; if there are no findings, say so briefly.",
  opts = nil,
}, ":CodexReview must request a non-mutating workspace review")

local opened
local original_open = terminal.open
local original_is_running = terminal.is_running
terminal.is_running = function()
  return false
end
terminal.open = function(args)
  opened = args
  return true
end

assert(codex.resume(), "resume must open Codex's picker")
assert_equal(opened, { "resume" }, "resume must not skip the session picker")
assert(codex.continue_session(), "continue must open the latest session")
assert_equal(opened, { "resume", "--last" }, "continue must target the latest session")

terminal.send = original_send
terminal.open = original_open
terminal.is_running = original_is_running

local root = vim.fn.tempname()
local nested = root .. "/nested/deeper"
assert(vim.fn.mkdir(nested, "p") == 1, "test directory must be created")
assert(vim.fn.mkdir(root .. "/.git", "p") == 1, "test Git marker must be created")
local file = nested .. "/file.lua"
assert(vim.fn.writefile({ "return true" }, file) == 0, "test file must be created")
assert_equal(util.git_root(file), root, "git root discovery must use the filesystem marker")
vim.fn.delete(root, "rf")

print("command and utility tests passed")
vim.cmd("qa!")
