vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("codex.config")
local terminal = require("codex.terminal")

config.setup({
  terminal_cmd = { "sh", "-c", "sleep 0.1; printf 'READY\\n'; cat" },
  startup_delay_ms = 300,
  enter_insert = false,
  focus_after_send = false,
  auto_close = false,
  keymaps = { enabled = false },
})

assert(terminal.send("cold-start text", { submit = false }), "cold-start text must be accepted")

vim.defer_fn(function()
  local state = terminal.get_state()
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local output = table.concat(lines, "\n")
  assert(output:find("READY", 1, true), "the test terminal did not start")
  assert(output:find("cold-start text", 1, true), "cold-start text was not delivered")
  terminal.stop()
  print("cold-start integration tests passed")
  vim.cmd("qa!")
end, 700)
