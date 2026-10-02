# codex.nvim

A lightweight Neovim integration for running the [OpenAI Codex CLI](https://github.com/openai/codex) in a vertical side panel.

The interaction model and default `<leader>a*` key layout are inspired by [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim), while the implementation uses Neovim's built-in terminal API and has no extra plugin dependencies.

### Features

- Open Codex in a right or left vertical side panel
- Reuse an independent Codex session for each project working directory
- Send the current file to Codex or reference a visual selection by file and line range
- Include the in-memory text of a modified visual selection, so unsaved changes are not lost
- Choose a listed Neovim buffer and insert its current contents into Codex
- Send current-buffer/all-buffer diagnostics or the quickfix list as bounded context
- Ask Codex for a non-mutating review of the current workspace changes
- Provide a Neo-tree mapping example for sending the selected file to Codex
- Send arbitrary prompts from a command or Lua
- Resume a prior Codex session from the built-in picker, or continue the most recent one
- Select a model and pass it to the next Codex process
- Use the current Git repository root as the working directory
- Configure the executable, working directory, environment, panel width, and keymaps
- No dependency on `toggleterm.nvim`, `plenary.nvim`, or other plugins

> **Diff behavior:** Codex runs as a native terminal process and applies changes through its own workflow. This plugin does not take over Claude Code's IDE diff protocol, so the diff commands are kept as compatibility commands and report that no nvim-managed diff is available.

### Requirements

- Neovim >= 0.10
- Codex CLI installed and available as `codex` in `$PATH`
- Codex CLI authenticated and ready to use

See the [Codex CLI repository](https://github.com/openai/codex) for installation and authentication instructions.

### Installation

#### lazy.nvim

```lua
{
  "storm-1614/codex.nvim",
  event = "VeryLazy",
  opts = {},
}
```

Or configure it directly:

```lua
{
  "storm-1614/codex.nvim",
  config = function()
    require("codex").setup()
  end,
}
```

#### Manual / local checkout

Clone the repository into a directory on Neovim's `runtimepath`, then add:

```lua
require("codex").setup()
```

For local development with lazy.nvim:

```lua
{
  dir = "~/path/to/codex.nvim",
  name = "codex.nvim",
  opts = {},
}
```

### Quick start

Open the side panel:

```vim
:Codex
```

Open it and send a prompt immediately:

```vim
:Codex fix the failing tests in this project
```

From Lua:

```lua
require("codex").open()
require("codex").send("Please explain the current function")
```

### Default keymaps

The default mappings follow the `<leader>a*` layout used by `claudecode.nvim`. If your `<leader>` is the space key, `<leader>ac` means `Space`, `a`, `c`.

| Key | Mode | Action |
| --- | --- | --- |
| `<leader>ac` | Normal | Toggle the Codex side panel |
| `<leader>af` | Normal | Focus the side panel; close it if already focused |
| `<leader>ar` | Normal | Open Codex's session picker |
| `<leader>aC` | Normal | Continue the most recent Codex session |
| `<leader>am` | Normal | Select a model |
| `<leader>ap` | Normal | Choose a buffer and insert its contents into Codex |
| `<leader>ae` | Normal | Send current-buffer diagnostics to Codex |
| `<leader>aR` | Normal | Review current workspace changes without editing |
| `<leader>ah` | Normal | Check Codex CLI, project directory, and session health |
| `<leader>ab` | Normal | Send the current file |
| `<leader>ab` | Visual | Insert the selected file and line range |
| `<leader>as` | Normal | Add the current file to the prompt for editing |
| `<leader>as` | Visual | Insert the selected file and line range for editing |
| `<leader>aa` | Normal | Accept current diff compatibility action |
| `<leader>ad` | Normal | Deny current diff compatibility action |
| `<leader>aA` | Normal | Accept all diff compatibility actions |
| `<leader>aD` | Normal | Deny all diff compatibility actions |
| `<leader>ax` | Normal | Stop Codex CLI |

### Commands

```vim
:Codex                             " Open Codex
:Codex fix the tests               " Open Codex and send a prompt
:CodexOpen                         " Open Codex
:CodexStart                        " Start Codex
:CodexToggle                       " Toggle the side panel
:CodexFocus                        " Focus the side panel
:CodexClose                        " Hide the panel, keep the process alive
:CodexStop                         " Stop Codex and close the panel
:CodexStatus                       " Show Codex status
:CodexHealth                       " Check CLI, current project directory, and session status
:CodexDiagnostics                  " Send current-buffer diagnostics to Codex
:CodexDiagnostics!                 " Send diagnostics from all buffers to Codex
:CodexQuickfix                     " Send the quickfix list to Codex
:CodexReview                       " Ask Codex to review workspace changes without editing
:CodexResume                       " Open Codex's session picker
:CodexContinue                     " Continue the latest session
:CodexAdd                          " Send the current file
:{start},{end}CodexAdd             " Send the current file with a line range
:CodexSend Explain this function   " Send a prompt and press Enter
:CodexSendText Explain this code   " Send text and press Enter
:CodexSendText! partial text       " Send text without pressing Enter
:CodexTreeAdd path/to/file.lua     " Insert a file path from a file tree without submitting
:CodexSelectModel                  " Select or enter a model
:CodexSelectBuffer                 " Choose a buffer and insert its contents
```

The diff compatibility commands are also available:

```vim
:CodexDiffAccept
:CodexDiffDeny
:CodexDiffAcceptAll
:CodexDiffDenyAll
:CodexCloseAllDiffs
```

### Configuration

The default configuration is:

```lua
require("codex").setup({
  terminal_cmd = "codex",
  cwd = nil,                         -- nil: use the current Git repository root
  git_repo_cwd = true,
  env = {},

  split_side = "right",             -- "left" or "right"
  split_width_percentage = 0.35,
  enter_insert = true,
  auto_close = true,
  focus_after_send = true,
  startup_delay_ms = 300,             -- settle the editable input before flushing queued sends
  selection = {
    include_text = "if_modified",    -- "never", "if_modified", or "always"
    max_chars = 12000,                -- bound in-memory selection context
  },
  diagnostics = {
    max_items = 50,                   -- bound diagnostic / quickfix entries
    max_chars = 12000,                -- bound diagnostic / quickfix context
  },

  terminal_win_opts = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    winfixwidth = true,
  },

  -- Leave empty to enter a model with :CodexSelectModel.
  models = {},

  keymaps = {
    enabled = true,
    prefix = "<leader>a",            -- used for omitted mappings below
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
})
```

Disable all default mappings if you prefer to define them yourself:

```lua
require("codex").setup({
  keymaps = {
    enabled = false,
  },
})
```

Use a custom Codex executable or fixed arguments:

```lua
require("codex").setup({
  terminal_cmd = {
    "/path/to/codex",
    "--sandbox",
    "workspace-write",
  },
})
```

After selecting a model, the next Codex process is started with:

```text
--model <selected-model>
```

### Buffer input

Use `:CodexSelectBuffer` (or `<leader>ap` by default) to select a listed,
loaded Neovim buffer. Its current contents, including unsaved changes, are
inserted into the Codex prompt without pressing Enter. This lets you add an
instruction before submitting it. Terminal buffers are excluded from the
picker.

When an insertion starts Codex, the text stays queued until its editable input
appears. Complete any login or folder-trust dialog normally; the plugin then
inserts the queued selections and buffers once, without submitting them.
`startup_delay_ms` is the settling time after the input appears, not a timeout
that sends text into a startup dialog.

### Visual-selection context

Visual selections always include their file path and line range. With the
default `selection.include_text = "if_modified"`, a selection from a modified
buffer also includes its current in-memory text in the Codex prompt. This keeps
Codex from reading stale on-disk source. Set `include_text = "never"` to keep
path-and-line references only, or `"always"` to send the selected text even for
saved buffers. `max_chars` bounds the pasted source and reports truncation in
the prompt.

### Project sessions

Codex terminals are isolated by their working directory (the current Git root
by default). Switching between repositories opens or focuses that repository's
own Codex process, so prompts are not sent to a session from another project.

### Diagnostics and review

`:CodexDiagnostics` sends diagnostics from the current buffer; use `!` to
include all available Neovim diagnostics. `:CodexQuickfix` sends the active
quickfix list. Both use the `diagnostics` limits above and ask Codex to inspect
the source before proposing a fix.

`:CodexReview` asks the running Codex CLI to inspect current workspace changes
and report findings only. The plugin does not execute `git` or edit files for
this command.

### Health check

Use `:CodexHealth` (or `<leader>ah`) to verify the configured CLI executable,
the current project's resolved working directory, and the matching Codex
terminal's state. It does not start Codex or inspect authentication credentials.

### Neo-tree

Add the following mapping inside Neo-tree's `window.mappings` to send its
selected file to Codex. It intentionally ignores directories.

```lua
["<leader>as"] = {
  function(state)
    local node = state.tree:get_node()
    if node.type == "file" then
      require("codex").tree_add(node.path)
    else
      vim.notify("Select a file in Neo-tree first", vim.log.levels.WARN)
    end
  end,
  desc = "Add selected file to Codex prompt",
},
```

### Testing

Run the complete syntax-check and headless Neovim test suite with:

```sh
make all
```

Run only the tests with `make test`, or syntax checks with `make check`.

### Working directory

By default, codex.nvim tries to start Codex from the Git repository root of the current file. To use a fixed directory:

```lua
require("codex").setup({
  cwd = "~/workspace/my-project",
  git_repo_cwd = false,
})
```

### Help

Inside Neovim:

```vim
:help codex.nvim
```
