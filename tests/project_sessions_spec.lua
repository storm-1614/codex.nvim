vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("codex.config")
local terminal = require("codex.terminal")

config.setup({
  terminal_cmd = { "sh", "-c", "cat" },
  startup_delay_ms = 0,
  enter_insert = false,
  focus_after_send = false,
  auto_close = false,
  keymaps = { enabled = false },
})

local function make_project()
  local root = vim.fn.tempname()
  assert(vim.fn.mkdir(root .. "/nested", "p") == 1, "project directory must be created")
  local file = root .. "/nested/example.lua"
  assert(vim.fn.writefile({ "return true" }, file) == 0, "project file must be created")
  assert(vim.fn.mkdir(root .. "/.git", "p") == 1, "Git marker must be created")
  return root, file
end

local root_a, file_a = make_project()
local root_b, file_b = make_project()

vim.cmd("edit " .. vim.fn.fnameescape(file_a))
local source_a_win = vim.api.nvim_get_current_win()
assert(terminal.open(), "project A terminal must open")
local session_a = terminal.get_state()
local job_a = session_a.job
local buffer_a = session_a.buf
assert(session_a.cwd == root_a, "project A must use its own Git root")
assert(terminal.close(), "closing project A must hide its terminal")
assert(vim.api.nvim_get_current_win() == source_a_win, "closing an active terminal must restore the source window")

vim.cmd("edit " .. vim.fn.fnameescape(file_b))
assert(terminal.open(), "project B terminal must open")
local session_b = terminal.get_state()
local job_b = session_b.job
local buffer_b = session_b.buf
assert(session_b ~= session_a, "different Git roots must use different sessions")
assert(session_b.cwd == root_b, "project B must use its own Git root")
assert(job_b ~= job_a and buffer_b ~= buffer_a, "projects must not share a process or terminal buffer")
assert(terminal.close(), "closing project B must hide its terminal")

vim.cmd("edit " .. vim.fn.fnameescape(file_a))
assert(terminal.open(), "opening project A again must reuse its terminal")
assert(terminal.get_state() == session_a, "project A must reactivate its original session")
assert(session_a.job == job_a and session_a.buf == buffer_a, "project A must keep its process and buffer")
terminal.stop()

vim.cmd("edit " .. vim.fn.fnameescape(file_b))
terminal.stop()
vim.fn.delete(root_a, "rf")
vim.fn.delete(root_b, "rf")

print("project session tests passed")
vim.cmd("qa!")
