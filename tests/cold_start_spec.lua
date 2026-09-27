vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("codex.config")
local terminal = require("codex.terminal")

config.setup({
  terminal_cmd = { "sh", "-c", "sleep 0.1; printf '\\033[?2004h\\033[?25h› READY\\n'; cat" },
  startup_delay_ms = 300,
  enter_insert = false,
  focus_after_send = false,
  auto_close = false,
  keymaps = { enabled = false },
})

assert(terminal.send("cold-start text", { submit = false }), "cold-start text must be accepted")
vim.defer_fn(function()
  assert(terminal.send("second cold-start text", { submit = false }), "a queued cold-start send must be accepted")
end, 50)

vim.defer_fn(function()
  local state = terminal.get_state()
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  -- Terminal screen wrapping is represented as buffer line breaks. These test
  -- messages contain no newlines, so ignore visual wrapping when asserting
  -- that queued writes reached the terminal.
  local output = table.concat(lines, "\n"):gsub("\n", "")
  assert(output:find("READY", 1, true), "the test terminal did not start")
  assert(output:find("cold-start text", 1, true), "cold-start text was not delivered")
  assert(output:find("second cold-start text", 1, true), "the queued cold-start text was not delivered")
  terminal.stop()
  print("cold-start integration tests passed")
  vim.cmd("qa!")
end, 700)
