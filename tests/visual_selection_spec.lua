vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("codex.util")
local terminal = require("codex.terminal")
local codex = require("codex")

local function assert_equal(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)))
end

local function reset_buffer(lines)
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

reset_buffer({ "alpha", "beta", "gamma", "delta" })
assert(util.visual_selection() == nil, "a new buffer must not have a visual selection")

-- Characterwise selections must preserve the exact selected characters.
vim.api.nvim_win_set_cursor(0, { 1, 1 })
vim.cmd("normal! v2l")
local character_selection = util.visual_selection()
assert(character_selection, "an active characterwise selection must be detected")
assert_equal(character_selection.lines, { "alpha" })
assert_equal(character_selection.text, "lph")
assert_equal(character_selection.bufnr, vim.api.nvim_get_current_buf(), "a selection must retain its source buffer")
assert_equal(character_selection.modified, vim.bo.modified, "a selection must retain its modified state")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
local saved_character_selection = util.visual_selection()
assert(saved_character_selection, "the last characterwise selection must be available")
assert_equal(saved_character_selection.text, "lph")

-- A visual mapping callback runs before '< and '> are updated.
local mapped_selection
local original_send_selection = terminal.send_selection
terminal.send_selection = function(selection)
  mapped_selection = selection
  return true
end
codex.setup({ keymaps = { send = "x", add_current = "y" } })
vim.cmd("normal! ggVj")
vim.cmd("normal x")
assert(mapped_selection, "the active visual selection must be available in the plugin mapping")
assert_equal(mapped_selection.start_line, 1)
assert_equal(mapped_selection.end_line, 2)
assert_equal(mapped_selection.lines, { "alpha", "beta" })
terminal.send_selection = original_send_selection
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

-- After leaving visual mode, the last-selection marks must still work.
local previous_selection = util.visual_selection()
assert(previous_selection, "the last visual selection must be available after leaving visual mode")
assert_equal(previous_selection.start_line, 1)
assert_equal(previous_selection.end_line, 2)
assert_equal(previous_selection.lines, { "alpha", "beta" })

-- Reverse linewise selections must be normalized to ascending line numbers.
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("normal! Vgg")
local reverse_selection = util.visual_selection()
assert(reverse_selection, "a reverse visual selection must be detected")
assert_equal(reverse_selection.start_line, 1)
assert_equal(reverse_selection.end_line, 4)
assert_equal(reverse_selection.lines, { "alpha", "beta", "gamma", "delta" })
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

-- Verify that sending a selection references its file and line range.
local sent_prompt
local sent_opts
local original_send = terminal.send
terminal.send = function(prompt, opts)
  sent_prompt = prompt
  sent_opts = opts
  return true
end
local sent = terminal.send_selection({
  file = "/tmp/example.lua",
  start_line = 3,
  end_line = 4,
  lines = { "gamma", "delta" },
})
terminal.send = original_send
assert(sent, "send_selection must report success when the sender succeeds")
assert_equal(sent_prompt, "Please inspect and process this file (lines 3-4): /tmp/example.lua")
assert_equal(sent_opts, { submit = false }, "selection reference must leave the prompt in the Codex input box")

print("visual selection tests passed")
vim.cmd("qa!")
