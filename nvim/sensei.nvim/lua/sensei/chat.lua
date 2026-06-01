-- Persistent chat buffer. History lives here (Lua); each turn the full
-- transcript is sent as JSON on stdin to `sensei chat`, which is stateless.

local M = {}

local uv = vim.uv or vim.loop
local NS = vim.api.nvim_create_namespace("sensei.chat")
local ARROW = "❯"
local LABEL_W = 6 -- width of widest label ("sensei")
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local THINKING = "\1" -- sentinel marker the render() loop swaps for an animated frame

local state = {
  win = nil,
  buf = nil,
  messages = {},
  busy = false,
  thinking_timer = nil,
  thinking_frame = 0,
}

local function strip_ansi(s)
  return (s:gsub("\27%[[%d;]*m", ""))
end

local function render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end

  local lines = {}
  local hls = {} -- { line_idx, col_s, col_e (-1 = EOL), hl_group }

  if #state.messages == 0 then
    table.insert(lines, "  sensei chat")
    table.insert(lines, "")
    table.insert(lines, "  i / a / <CR>  ask a question")
    table.insert(hls, { #lines - 1, 0, -1, "SenseiHint" })
    table.insert(lines, "  q / <Esc>     close")
    table.insert(hls, { #lines - 1, 0, -1, "SenseiHint" })
    table.insert(lines, "")
  else
    for _, m in ipairs(state.messages) do
      local is_user = m.role == "user"
      local label = is_user and "you" or "sensei"
      local group = is_user and "SenseiYou" or "SenseiSensei"
      local pad = string.rep(" ", LABEL_W - #label)
      local head = label .. pad .. "  " .. ARROW .. "  "
      local indent = string.rep(" ", vim.fn.strdisplaywidth(head))

      local is_thinking = (m.content == THINKING)
      local body
      if is_thinking then
        local glyph = SPINNER[(state.thinking_frame % #SPINNER) + 1]
        local dots = string.rep(" .", (state.thinking_frame % 4))
        body = glyph .. "  thinking" .. dots
      else
        body = strip_ansi(m.content)
      end

      local first = true
      local head_idx
      for chunk in (body .. "\n"):gmatch("(.-)\n") do
        if first then
          head_idx = #lines
          table.insert(lines, head .. chunk)
          first = false
        else
          table.insert(lines, indent .. chunk)
        end
      end

      table.insert(hls, { head_idx, 0, #label, group })
      local arrow_s = #label + #pad + 2 -- two spaces before the arrow
      table.insert(hls, { head_idx, arrow_s, arrow_s + #ARROW, "SenseiArrow" })
      if is_thinking then
        table.insert(hls, { head_idx, #head, -1, "SenseiThinking" })
      end

      table.insert(lines, "")
      table.insert(lines, "")
    end
  end

  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  for _, h in ipairs(hls) do
    local end_col = (h[3] == -1) and #(lines[h[1] + 1] or "") or h[3]
    pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, h[1], h[2], {
      end_row = h[1],
      end_col = end_col,
      hl_group = h[4],
    })
  end
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { math.max(1, #lines), 0 })
  end
end

local function stop_thinking()
  if state.thinking_timer then
    pcall(function()
      state.thinking_timer:stop()
      state.thinking_timer:close()
    end)
    state.thinking_timer = nil
  end
end

local function start_thinking()
  stop_thinking()
  state.thinking_frame = 0
  local timer = uv.new_timer()
  state.thinking_timer = timer
  timer:start(0, 120, vim.schedule_wrap(function()
    if not state.thinking_timer then
      return
    end
    state.thinking_frame = state.thinking_frame + 1
    render()
  end))
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
    stop_thinking()
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
    table.insert(state.messages, { role = "assistant", content = THINKING })
    start_thinking()

    run_chat(config, payload, function(reply, err)
      stop_thinking()

      local last = state.messages[#state.messages]
      if last and last.content == THINKING then
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
  stop_thinking()
  state.messages = {}
  render()
end

return M
