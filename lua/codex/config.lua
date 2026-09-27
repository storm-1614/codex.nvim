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
  -- Wait this long after an editable Codex composer is visible before
  -- flushing startup text. Startup dialogs keep the text queued.
  startup_delay_ms = 300,
  -- Visual selections normally reference a file and line range. Include the
  -- in-memory text when the buffer has unsaved changes so Codex sees the same
  -- source the user sees.
  selection = {
    include_text = "if_modified", -- "never", "if_modified", or "always"
    max_chars = 12000,
  },
  -- Bounds diagnostic context before it is sent to Codex. This avoids a noisy
  -- language server or quickfix list overwhelming the prompt.
  diagnostics = {
    max_items = 50,
    max_chars = 12000,
  },
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
    select_buffer = "<leader>ap",
    diagnostics = "<leader>ae",
    review = "<leader>aR",
    health = "<leader>ah",
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

local keymap_suffixes = {
  toggle = "c",
  focus = "f",
  resume = "r",
  continue_session = "C",
  select_model = "m",
  select_buffer = "p",
  diagnostics = "e",
  review = "R",
  health = "h",
  add_current = "b",
  send = "s",
  tree_add = "s",
  diff_accept = "a",
  diff_deny = "d",
  diff_accept_all = "A",
  diff_deny_all = "D",
  stop = "x",
}

M.values = vim.deepcopy(defaults)

local function assert_type(name, value, expected)
  if type(value) ~= expected then
    error(string.format("codex.nvim: %s must be a %s", name, expected))
  end
end

local function assert_boolean(name, value)
  assert_type(name, value, "boolean")
end

local function assert_finite_number(name, value)
  assert_type(name, value, "number")
  if value ~= value or math.abs(value) == math.huge then
    error("codex.nvim: " .. name .. " must be finite")
  end
end

local function validate_command(command)
  if type(command) == "string" then
    return
  end
  if type(command) ~= "table" or #command == 0 then
    error("codex.nvim: terminal_cmd must be a command string or a non-empty argv list")
  end
  for index, arg in ipairs(command) do
    if type(arg) ~= "string" or arg == "" then
      error(string.format("codex.nvim: terminal_cmd[%d] must be a non-empty string", index))
    end
  end
end

local function validate_env(env)
  assert_type("env", env, "table")
  for name, value in pairs(env) do
    if type(name) ~= "string" or type(value) ~= "string" then
      error("codex.nvim: env must map string names to string values")
    end
  end
end

local function validate_models(models)
  assert_type("models", models, "table")
  for index, model in ipairs(models) do
    if type(model) ~= "string" or model == "" then
      error(string.format("codex.nvim: models[%d] must be a non-empty string", index))
    end
  end
end

local function validate_selection(selection)
  assert_type("selection", selection, "table")
  if selection.include_text ~= "never"
      and selection.include_text ~= "if_modified"
      and selection.include_text ~= "always" then
    error("codex.nvim: selection.include_text must be 'never', 'if_modified', or 'always'")
  end
  assert_finite_number("selection.max_chars", selection.max_chars)
  if selection.max_chars <= 0 or selection.max_chars % 1 ~= 0 then
    error("codex.nvim: selection.max_chars must be a positive integer")
  end
end

local function validate_diagnostics(diagnostics)
  assert_type("diagnostics", diagnostics, "table")
  for _, name in ipairs({ "max_items", "max_chars" }) do
    assert_finite_number("diagnostics." .. name, diagnostics[name])
    if diagnostics[name] <= 0 or diagnostics[name] % 1 ~= 0 then
      error("codex.nvim: diagnostics." .. name .. " must be a positive integer")
    end
  end
end

local function apply_keymap_prefix(values, opts)
  local configured_keymaps = opts.keymaps or {}
  if configured_keymaps.prefix == nil then
    return
  end
  for name, suffix in pairs(keymap_suffixes) do
    if configured_keymaps[name] == nil then
      values.keymaps[name] = values.keymaps.prefix .. suffix
    end
  end
end

local function validate_keymaps(keymaps)
  assert_type("keymaps", keymaps, "table")
  assert_boolean("keymaps.enabled", keymaps.enabled)
  assert_type("keymaps.prefix", keymaps.prefix, "string")
  for name in pairs(keymap_suffixes) do
    if type(keymaps[name]) ~= "string" or keymaps[name] == "" then
      error("codex.nvim: keymaps." .. name .. " must be a non-empty string")
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  assert_type("setup options", opts, "table")
  local values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  apply_keymap_prefix(values, opts)

  validate_command(values.terminal_cmd)
  if values.cwd ~= nil then
    assert_type("cwd", values.cwd, "string")
  end
  assert_boolean("git_repo_cwd", values.git_repo_cwd)
  validate_env(values.env)
  if values.split_side ~= "left" and values.split_side ~= "right" then
    error("codex.nvim: split_side must be 'left' or 'right'")
  end
  assert_finite_number("split_width_percentage", values.split_width_percentage)
  if values.split_width_percentage <= 0
      or values.split_width_percentage >= 1 then
    error("codex.nvim: split_width_percentage must be between 0 and 1")
  end
  assert_boolean("enter_insert", values.enter_insert)
  assert_boolean("auto_close", values.auto_close)
  assert_boolean("focus_after_send", values.focus_after_send)
  assert_finite_number("startup_delay_ms", values.startup_delay_ms)
  if values.startup_delay_ms < 0 then
    error("codex.nvim: startup_delay_ms must be a non-negative number")
  end
  validate_selection(values.selection)
  validate_diagnostics(values.diagnostics)
  assert_type("terminal_win_opts", values.terminal_win_opts, "table")
  validate_models(values.models)
  validate_keymaps(values.keymaps)
  for _, callback_name in ipairs({ "on_open", "on_close", "on_exit" }) do
    local callback = values[callback_name]
    if callback ~= nil and type(callback) ~= "function" then
      error("codex.nvim: " .. callback_name .. " must be a function or nil")
    end
  end

  -- Do not leave the plugin in a partially invalid state if validation fails.
  M.values = values
end

function M.get()
  return M.values
end

return M
