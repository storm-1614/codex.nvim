local M = {}

local defaults = {
  -- A string is convenient for the default CLI. A list can be used when the
  -- executable needs fixed arguments, e.g. { "codex", "--sandbox", "workspace-write" }.
  terminal_cmd = "codex",
  cwd = nil,
  -- When true, use the repository root of the current buffer when possible.
  git_repo_cwd = true,
  env = {},

  split_side = "right",
  split_width_percentage = 0.35,
  enter_insert = true,
  auto_close = true,
  focus_after_send = true,
  terminal_win_opts = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    winfixwidth = true,
  },

  -- Used by :CodexSelectModel. Keep this empty if the installed CLI changes
  -- its model catalogue frequently; the command then asks for a model name.
  models = {},

  -- Matches claudecode.nvim's <leader>a* layout. Set to false to opt out.
  keymaps = {
    enabled = true,
    prefix = "<leader>a",
    toggle = "<leader>ac",
    focus = "<leader>af",
    resume = "<leader>ar",
    continue_session = "<leader>aC",
    select_model = "<leader>am",
    add_current = "<leader>ab",
    send = "<leader>as",
    tree_add = "<leader>as",
    diff_accept = "<leader>aa",
    diff_deny = "<leader>ad",
    diff_accept_all = "<leader>aA",
    diff_deny_all = "<leader>aD",
    stop = "<leader>ax",
  },

  -- `on_open`, `on_close`, and `on_exit` receive the terminal state table.
  on_open = nil,
  on_close = nil,
  on_exit = nil,
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)

  if M.values.split_side ~= "left" and M.values.split_side ~= "right" then
    error("codex.nvim: split_side must be 'left' or 'right'")
  end
  if type(M.values.split_width_percentage) ~= "number"
      or M.values.split_width_percentage <= 0
      or M.values.split_width_percentage >= 1 then
    error("codex.nvim: split_width_percentage must be between 0 and 1")
  end
end

function M.get()
  return M.values
end

return M
