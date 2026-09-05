vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local codex = require("codex")
local config = require("codex.config")

local function mapping_exists(lhs, mode)
  return vim.fn.maparg(lhs, mode) ~= ""
end

codex.setup({ keymaps = { prefix = "<leader>z" } })
assert(config.get().keymaps.toggle == "<leader>zc", "prefix must derive omitted keymaps")
assert(config.get().keymaps.diagnostics == "<leader>ze", "prefix must derive the diagnostics keymap")
assert(config.get().keymaps.review == "<leader>zR", "prefix must derive the review keymap")
assert(mapping_exists("\\zc", "n"), "the derived toggle keymap must be installed")
assert(mapping_exists("\\ze", "n"), "the derived diagnostics keymap must be installed")
assert(mapping_exists("\\zR", "n"), "the derived review keymap must be installed")
assert(not mapping_exists("\\ac", "n"), "the old default toggle keymap must not be installed")

codex.setup({ keymaps = { toggle = "<F9>" } })
assert(mapping_exists("<F9>", "n"), "a configured keymap must be installed")
codex.setup({ keymaps = { toggle = "<F10>" } })
assert(mapping_exists("<F10>", "n"), "a replacement keymap must be installed")
assert(not mapping_exists("<F9>", "n"), "reconfiguring must remove the stale keymap")

codex.setup({ keymaps = { enabled = false } })
assert(not mapping_exists("<F10>", "n"), "disabling keymaps must remove installed keymaps")

print("keymap lifecycle tests passed")
vim.cmd("qa!")
