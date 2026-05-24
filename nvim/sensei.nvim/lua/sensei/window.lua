local M = {}

local function run_sensei(args)
  local cmd = vim.list_extend({}, args)
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return result
end

local function strip_ansi(lines)
  local clean = {}
  for _, line in ipairs(lines) do
    -- strip ANSI escape codes
    local stripped = line:gsub("\27%[[%d;]*m", "")
    table.insert(clean, stripped)
  end
  return clean
end

function M.open(lines, config, dismiss_timeout)
  lines = strip_ansi(lines)

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.max(width, config.width or 54)

  local height = #lines
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "none",
  })

  vim.api.nvim_win_set_option(win, "winblend", 10)
  vim.api.nvim_win_set_option(win, "wrap", false)

  -- highlight the window content
  vim.api.nvim_win_set_option(win, "winhighlight", "Normal:Identifier")

  -- close on Esc or any cursor movement
  local function close()
    pcall(vim.api.nvim_win_close, win, true)
  end

  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })

  local group = vim.api.nvim_create_augroup("SenseiWindow" .. win, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
    group = group,
    callback = function()
      close()
      vim.api.nvim_del_augroup_by_id(group)
    end,
    once = true,
  })

  if (dismiss_timeout or 0) > 0 then
    vim.defer_fn(function()
      pcall(vim.api.nvim_win_close, win, true)
    end, dismiss_timeout)
  end
end

function M.show_tip(config, topic)
  local args = { config.binary, "tip" }
  if topic then
    vim.list_extend(args, { "--topic", topic })
  end
  local lines = run_sensei(args)
  if lines then
    M.open(lines, config, config.dismiss_timeout)
  end
end

function M.show_explain(config, text)
  local args = { config.binary, "explain", text }
  local lines = run_sensei(args)
  if lines then
    M.open(lines, config, 0)
  end
end

function M.show_ask(config, question)
  local args = { config.binary, "ask", question }
  local lines = run_sensei(args)
  if lines then
    M.open(lines, config, 0)
  end
end

return M
