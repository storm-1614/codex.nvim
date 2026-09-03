vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("codex.config")

config.setup({
  terminal_cmd = { "codex", "--version" },
  startup_delay_ms = 123,
  keymaps = { enabled = false },
})

local previous = vim.deepcopy(config.get())
local ok, err = pcall(config.setup, { startup_delay_ms = -1 })
assert(not ok, "a negative startup delay must be rejected")
assert(tostring(err):find("startup_delay_ms", 1, true), "the validation error must name the invalid option")
assert(vim.deep_equal(config.get(), previous), "a rejected setup call must preserve the last valid configuration")

ok, err = pcall(config.setup, { terminal_cmd = {} })
assert(not ok, "an empty terminal argv list must be rejected")
assert(tostring(err):find("terminal_cmd", 1, true), "the terminal command error must be actionable")
assert(vim.deep_equal(config.get(), previous), "an invalid command must not replace the valid configuration")

ok, err = pcall(config.setup, { env = { CODEX_TEST = 42 } })
assert(not ok, "terminal environment values must be strings")
assert(tostring(err):find("env", 1, true), "the environment error must be actionable")
assert(vim.deep_equal(config.get(), previous), "an invalid environment must not replace the valid configuration")

print("configuration tests passed")
vim.cmd("qa!")
