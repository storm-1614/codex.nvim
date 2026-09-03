# codex.nvim

A lightweight Neovim integration for running the [OpenAI Codex CLI](https://github.com/openai/codex) in a vertical side panel.

The interaction model and default `<leader>a*` key layout are inspired by [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim), while the implementation uses Neovim's built-in terminal API and has no extra plugin dependencies.

### Features

- Open Codex in a right or left vertical side panel
- Reuse the same Codex session when the panel is hidden
- Send the current file to Codex or reference a visual selection by file and line range
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
| `<leader>ab` | Normal | Send the current file |
| `<leader>ab` | Visual | Insert the selected file and line range |
| `<leader>as` | Normal | Add the current file |
| `<leader>as` | Visual | Insert the selected file and line range |
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
:CodexResume                       " Open Codex's session picker
:CodexContinue                     " Continue the latest session
:CodexAdd                          " Send the current file
:{start},{end}CodexAdd             " Send the current file with a line range
:CodexSend Explain this function   " Send a prompt and press Enter
:CodexSendText Explain this code   " Send text and press Enter
:CodexSendText! partial text       " Send text without pressing Enter
:CodexTreeAdd path/to/file.lua     " Send a file path from a file tree
:CodexSelectModel                  " Select or enter a model
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
  startup_delay_ms = 300,             -- settle the TUI before flushing queued sends

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
