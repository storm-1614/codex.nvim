vim.cmd("set noswapfile")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local codex = require("codex")
local terminal = require("codex.terminal")

local function assert_equal(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)))
end

codex.setup({ keymaps = { enabled = false } })

local buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buffer, "/tmp/codex-buffer-input.lua")
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "local answer = 42", "return answer" })

local sent
local original_send = terminal.send
terminal.send = function(text, opts)
  sent = { text = text, opts = opts }
  return true
end

assert(codex.send_buffer(buffer), "a loaded buffer must be accepted as Codex input")
assert_equal(sent, {
  text = "local answer = 42\nreturn answer",
  opts = { submit = false },
}, "buffer contents must be inserted without submitting")

local original_select = vim.ui.select
local select_prompt
local displayed
vim.ui.select = function(items, opts, on_choice)
  select_prompt = opts.prompt
  for _, item in ipairs(items) do
    if item.bufnr == buffer then
      displayed = opts.format_item(item)
      on_choice(item)
      return
    end
  end
  error("the input buffer must be available in the picker")
end

sent = nil
assert(codex.select_buffer(), "opening the buffer picker must succeed")
assert_equal(select_prompt, "Select a buffer to insert into Codex")
assert_equal(displayed, buffer .. ": /tmp/codex-buffer-input.lua")
assert_equal(sent, {
  text = "local answer = 42\nreturn answer",
  opts = { submit = false },
}, "the picker must insert the selected buffer contents")

vim.ui.select = original_select
terminal.send = original_send
vim.api.nvim_buf_delete(buffer, { force = true })

print("buffer input tests passed")
vim.cmd("qa!")
