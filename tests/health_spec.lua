vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local codex = require("codex")
local config = require("codex.config")
local terminal = require("codex.terminal")
local util = require("codex.util")

config.setup({
  terminal_cmd = "/bin/sh",
  cwd = "/tmp",
  git_repo_cwd = false,
  keymaps = { enabled = false },
})

assert(terminal.peek_state() == nil, "health tests must begin without a terminal session")
local report = codex.health_report()
assert(report.ok, "an executable CLI and valid cwd must produce a healthy report")
assert(report.cli.available and report.cli.path ~= "", "health must resolve the configured CLI executable")
assert(report.cwd.available and report.cwd.path:match("^/tmp/?$"), "health must validate the configured working directory")
assert(not report.session.started, "a health check must not create a terminal session")

local original_notify = util.notify
local message
util.notify = function(text)
  message = text
end
local ok = codex.health()
util.notify = original_notify
assert(ok, "health must return true for a valid report")
assert(message:find("Codex 健康检查", 1, true), "health must show a readable report")
assert(message:find("登录状态", 1, true), "health must disclose that credentials are not probed")

config.setup({
  terminal_cmd = "codex-nvim-command-that-does-not-exist",
  cwd = "/tmp/codex-nvim-directory-that-does-not-exist",
  git_repo_cwd = false,
  keymaps = { enabled = false },
})
report = codex.health_report()
assert(not report.ok, "a missing CLI or working directory must make health fail")
assert(not report.cli.available, "health must flag an unavailable CLI")
assert(not report.cwd.available, "health must flag an unavailable working directory")

print("health tests passed")
vim.cmd("qa!")
