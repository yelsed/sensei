-- Persistent chat buffer. History lives here (Lua); each turn the full
-- transcript is sent as JSON on stdin to `sensei chat`, which is stateless.

local M = {}

local state = {
  win = nil,
  buf = nil,
  messages = {},
  busy = false,
}

local PLACEHOLDER = "…thinking…"

local function strip_ansi(s)
  return (s:gsub("\27%[[%d;]*m", ""))
end

local function render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end

  local lines = {}
  if #state.messages == 0 then
    lines = {
      "  sensei chat",
      "",
      "  i / a / <CR>  ask a question",
      "  q / <Esc>     close",
      "",
    }
  else
    for _, m in ipairs(state.messages) do
      local prefix = m.role == "user" and "you > " or "sensei > "
      local indent = string.rep(" ", #prefix)
      local body = strip_ansi(m.content)
      local first = true
      for chunk in (body .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, (first and prefix or indent) .. chunk)
        first = false
      end
      table.insert(lines, "")
    end
  end

  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { math.max(1, #lines), 0 })
  end
end

-- Run `sensei chat`, feeding `payload` (JSON transcript) on stdin. Async so the
-- editor stays responsive while Ollama thinks.
local function run_chat(config, payload, on_done)
  local stdout, stderr = {}, {}
  local job = vim.fn.jobstart({ config.binary, "chat" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      stdout = data
    end,
    on_stderr = function(_, data)
      stderr = data
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          on_done(vim.trim(table.concat(stdout, "\n")), nil)
        else
          on_done(nil, vim.trim(table.concat(stderr, " ")))
        end
      end)
    end,
  })

  if job <= 0 then
    on_done(nil, "could not start '" .. config.binary .. "'")
    return
  end

  vim.fn.chansend(job, payload)
  vim.fn.chanclose(job, "stdin")
end

function M.open(config)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  local buf = (state.buf and vim.api.nvim_buf_is_valid(state.buf)) and state.buf
    or vim.api.nvim_create_buf(false, true)
  state.buf = buf
  vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")

  local ui = vim.api.nvim_list_uis()[1]
  local width = math.max(40, math.floor(ui.width * 0.7))
  local height = math.max(10, math.floor(ui.height * 0.6))
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " sensei chat ",
    title_pos = "center",
  })
  state.win = win
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)
  vim.api.nvim_win_set_option(win, "winhighlight", "FloatBorder:Identifier")

  local function close()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      pcall(vim.api.nvim_win_close, state.win, true)
    end
    state.win = nil
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "i", function() M.ask(config) end, opts)
  vim.keymap.set("n", "a", function() M.ask(config) end, opts)
  vim.keymap.set("n", "<CR>", function() M.ask(config) end, opts)

  render()
end

function M.ask(config)
  M.open(config)

  if state.busy then
    return
  end

  vim.ui.input({ prompt = "you > " }, function(input)
    if not input or input == "" then
      return
    end

    table.insert(state.messages, { role = "user", content = input })
    local payload = vim.json.encode(state.messages)

    state.busy = true
    table.insert(state.messages, { role = "assistant", content = PLACEHOLDER })
    render()

    run_chat(config, payload, function(reply, err)
      -- drop the placeholder
      local last = state.messages[#state.messages]
      if last and last.content == PLACEHOLDER then
        table.remove(state.messages)
      end

      if reply and reply ~= "" then
        table.insert(state.messages, { role = "assistant", content = reply })
      else
        local hint = err and (" (" .. err .. ")") or ""
        table.insert(state.messages, {
          role = "assistant",
          content = "[Ollama unavailable — is it running? Try :SenseiHealth]" .. hint,
        })
      end

      state.busy = false
      render()
    end)
  end)
end

-- Clear the transcript and start fresh.
function M.reset()
  state.messages = {}
  render()
end

return M
