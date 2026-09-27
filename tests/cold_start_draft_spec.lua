vim.cmd('set noswapfile')
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local codex = require('codex')
local terminal = require('codex.terminal')

codex.setup({
  terminal_cmd = { 'python3', vim.fn.getcwd() .. '/tests/fixtures/slow_tui.py' },
  startup_delay_ms = 100,
  enter_insert = false,
  focus_after_send = false,
  auto_close = false,
  selection = { include_text = 'always' },
  keymaps = { enabled = true },
})

local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(source, '/tmp/codex-cold-selection.lua')
vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'COLD_SELECTION_MARKER', 'second selected line' })
vim.api.nvim_feedkeys('Vj', 'nx', false)
local mapping = vim.fn.maparg('<leader>as', 'v', false, true)
assert(mapping.callback(), 'the actual visual send mapping must accept the selection')

local extra = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(extra, 0, -1, false, { 'QUEUED_BUFFER_MARKER' })
assert(codex.send_buffer(extra), 'buffer insertion during startup must be queued too')

local ok = vim.wait(4000, function()
  local state = terminal.get_state()
  local screen = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), '\n'):gsub('\n', '')
  return screen:find('QUEUED_BUFFER_MARKER', 1, true) ~= nil
end, 20)
local state = terminal.get_state()
local screen = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), '\n'):gsub('\n', '')
terminal.stop()
if not ok or not screen:find('COLD_SELECTION_MARKER', 1, true)
    or screen:find('UNEXPECTED_SUBMIT', 1, true) then
  print('cold-start draft missing or unexpectedly submitted: ' .. screen)
  vim.cmd('cquit 1')
end
local _, selections = screen:gsub('COLD_SELECTION_MARKER', '')
local _, buffers = screen:gsub('QUEUED_BUFFER_MARKER', '')
assert(selections == 1 and buffers == 1, 'queued drafts must be inserted exactly once')
assert(screen:find('COLD_SELECTION_MARKER', 1, true) < screen:find('QUEUED_BUFFER_MARKER', 1, true),
  'queued drafts must retain their order')
print('cold-start visual selection and buffer integration tests passed')
vim.cmd('qa!')
