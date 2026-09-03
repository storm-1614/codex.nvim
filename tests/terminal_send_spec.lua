vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("codex.config")
local terminal = require("codex.terminal")

local function assert_equal(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)))
end

config.setup({
  keymaps = { enabled = false },
  focus_after_send = false,
  auto_close = false,
  startup_delay_ms = 300,
})

local state = terminal.get_state()
local original_buf = vim.api.nvim_get_current_buf()
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, buffer)
state.buf = buffer
state.job = 42
state.win = vim.api.nvim_get_current_win()
state.starting = false
state.pending_sends = {}
vim.b[buffer].terminal_job_id = 42

local original_jobwait = vim.fn.jobwait
local original_chansend = vim.fn.chansend
local original_defer_fn = vim.defer_fn
local sent = {}
local deferred = {}

vim.fn.jobwait = function()
  return { -1 }
end
vim.fn.chansend = function(channel, payload)
  table.insert(sent, { channel = channel, payload = payload })
  return #payload
end
vim.defer_fn = function(callback, delay)
  table.insert(deferred, { callback = callback, delay = delay })
end

local ok = terminal.send("first line\nsecond line")
assert(ok, "multi-line text must be sent successfully")
assert_equal(sent, {
  {
    channel = 42,
    payload = "\27[200~first line\nsecond line\27[201~\r",
  },
}, "multi-line text must be bracketed and submitted in one write")

sent = {}
ok = terminal.send("single line", { submit = false })
assert(ok, "submit=false must still send text")
assert_equal(sent, { { channel = 42, payload = "single line" } })

sent = {}
ok = terminal.send_selection({
  file = "/tmp/example.lua",
  start_line = 3,
  end_line = 4,
  lines = { "gamma", "delta" },
})
assert(ok, "a visual selection must be sent successfully")
assert_equal(sent, {
  {
    channel = 42,
    payload = "Please inspect and process this file (lines 3-4): /tmp/example.lua",
  },
}, "a visual selection must reference its file and line range without submitting")

-- A missing terminal must be opened before the selected text is inserted.
local original_termopen = vim.fn.termopen
state.buf = nil
state.win = nil
state.job = nil
vim.fn.termopen = function()
  return 42
end
sent = {}
ok = terminal.send("opened selection", { submit = false })
assert(ok, "text must be queued when Codex was not already open")
assert(state.buf and state.win and state.job == 42, "sending text must open Codex when necessary")
assert_equal(sent, {}, "cold-start text must wait for the Codex prompt")
assert_equal(#deferred, 1, "opening starts one startup queue timer")
assert_equal(deferred[1].delay, 300)

ok = terminal.send("queued second", { submit = false })
assert(ok, "a second cold-start send must be accepted")
assert_equal(#deferred, 1, "all cold-start sends must share the startup timer")
deferred[1].callback()
assert_equal(sent, {
  { channel = 42, payload = "opened selection" },
  { channel = 42, payload = "queued second" },
}, "cold-start text must be flushed once, in FIFO order")
local opened_buf = state.buf
terminal.close()
state.job = nil
if vim.api.nvim_buf_is_valid(opened_buf) then
  vim.api.nvim_buf_delete(opened_buf, { force = true })
end
vim.fn.termopen = original_termopen

-- A running process with a hidden split must be reopened before insertion.
local original_open = terminal.open
local reopened = false
state.buf = buffer
state.win = nil
state.job = 42
terminal.open = function()
  reopened = true
  state.win = vim.api.nvim_get_current_win()
  return true
end
sent = {}
ok = terminal.send("hidden selection", { submit = false })
assert(ok, "text insertion must succeed when the split was hidden")
assert(reopened, "a hidden terminal split must be reopened")
assert_equal(sent, { { channel = 42, payload = "hidden selection" } })
terminal.open = original_open

vim.fn.jobwait = original_jobwait
vim.fn.chansend = original_chansend
vim.defer_fn = original_defer_fn
vim.api.nvim_win_set_buf(0, original_buf)
vim.api.nvim_buf_delete(buffer, { force = true })
state.buf = nil
state.job = nil
state.win = nil
state.starting = false
state.pending_sends = {}

print("terminal send tests passed")
vim.cmd("qa!")
