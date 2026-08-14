local M = {}

function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codex.nvim" })
end

function M.is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function M.is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

function M.current_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":p")
end

function M.git_root(path)
  if not path then
    return nil
  end
  local dir = vim.fn.fnamemodify(path, ":h")
  local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, {
    text = true,
    timeout = 1000,
  }):wait()
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

function M.cwd(config)
  if config.cwd and config.cwd ~= "" then
    return vim.fn.fnamemodify(vim.fn.expand(config.cwd), ":p")
  end
  if config.git_repo_cwd then
    return M.git_root(M.current_file()) or vim.loop.cwd()
  end
  return vim.loop.cwd()
end

function M.command_list(command)
  if type(command) == "table" then
    return vim.deepcopy(command)
  end
  if type(command) ~= "string" or command == "" then
    return { "codex" }
  end
  -- The common case is a single executable. Shell parsing is intentionally
  -- avoided so termopen never invokes an intermediate shell.
  return { command }
end

local function visual_mode()
  local mode = vim.fn.mode()
  if mode:match("^[vV\22]") then
    return mode:sub(1, 1)
  end
  local last_mode = vim.fn.visualmode()
  if last_mode == "v" or last_mode == "V" or last_mode == "\22" then
    return last_mode
  end
  return nil
end

local function ordered_positions(first, second)
  local first_row, first_col = first[2], first[3]
  local second_row, second_col = second[2], second[3]
  if first_row < second_row or (first_row == second_row and first_col <= second_col) then
    return first_row, first_col, second_row, second_col
  end
  return second_row, second_col, first_row, first_col
end

local function selection_text(lines, mode, start_col, end_col)
  if mode == "V" then
    return table.concat(lines, "\n")
  end

  if mode == "\22" then
    local selected = {}
    for _, line in ipairs(lines) do
      local first_col = math.max(1, math.min(start_col, #line + 1))
      local last_col = math.max(1, math.min(end_col, #line + 1))
      selected[#selected + 1] = string.sub(line, first_col, last_col)
    end
    return table.concat(selected, "\n")
  end

  if #lines == 0 then
    return nil
  end
  local first = lines[1] or ""
  local last = lines[#lines] or ""
  start_col = math.max(1, math.min(start_col, #first + 1))
  end_col = math.max(1, math.min(end_col, #last + 1))

  if #lines == 1 then
    return string.sub(first, start_col, end_col)
  end

  local selected = { string.sub(first, start_col) }
  for index = 2, #lines - 1 do
    selected[#selected + 1] = lines[index]
  end
  selected[#selected + 1] = string.sub(last, 1, end_col)
  return table.concat(selected, "\n")
end

function M.visual_selection()
  local mode = visual_mode()
  if not mode then
    return nil
  end

  local start
  local finish
  if vim.fn.mode():match("^[vV\22]") then
    -- A Lua callback used by a visual-mode mapping runs before Neovim leaves
    -- visual mode. Read the visual anchor and current cursor in that case.
    start = vim.fn.getpos("v")
    finish = vim.fn.getpos(".")
  else
    -- Once visual mode has ended, Neovim stores the last selection in these
    -- marks. This also keeps the helper useful from normal-mode commands.
    start = vim.fn.getpos("'<")
    finish = vim.fn.getpos("'>")
  end

  if start[2] == 0 or finish[2] == 0 then
    return nil
  end

  local start_line, start_col, end_line, end_col = ordered_positions(start, finish)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil
  end

  local text = selection_text(lines, mode, start_col, end_col)
  if not text or text == "" then
    return nil
  end

  return {
    lines = lines,
    text = text,
    start_line = start_line,
    end_line = end_line,
    file = M.current_file(),
  }
end

function M.escape_prompt(text)
  return (text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

return M
