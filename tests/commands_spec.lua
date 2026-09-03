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
