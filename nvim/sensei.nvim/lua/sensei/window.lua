local M = {}

local uv = vim.uv or vim.loop
math.randomseed(os.time())

local function strip_ansi(lines)
  local clean = {}
  for _, line in ipairs(lines or {}) do
    table.insert(clean, (line:gsub("\27%[[%d;]*m", "")))
  end
  return clean
end

local function has_content(lines)
  for _, l in ipairs(lines or {}) do
    if l ~= "" then return true end
  end
  return false
end

-- Strip the binary's ╭──╮ box. Returns inner text lines + the 💡 label (title).
-- The binary draws a fixed-width box for the terminal; in nvim we draw our own
-- border at a width we control, so we peel the box off and keep just the text.
local function unbox(lines)
  local text, title = {}, nil
  for _, l in ipairs(lines) do
    local first = l:sub(1, 3)
    if first == "╭" or first == "╰" then
      -- top/bottom border: drop
    elseif l:sub(1, 3) == "│" then
      local inner = l:gsub("^│%s*", ""):gsub("%s*│$", "")
      inner = vim.trim(inner)
      if inner:find("💡") then
        title = " " .. inner .. " "
      else
        text[#text + 1] = inner
      end
    else
      text[#text + 1] = l -- not boxed (e.g. error lines): keep as-is
    end
  end
  -- drop leading/trailing blanks
  while #text > 0 and text[1] == "" do table.remove(text, 1) end
  while #text > 0 and text[#text] == "" do table.remove(text) end
  return text, title
end

-- Word-wrap one paragraph to width. Long unbreakable tokens pass through.
local function wrap_text(lines, width)
  local out = {}
  for _, para in ipairs(lines) do
    if para == "" then
      out[#out + 1] = ""
    else
      local cur = ""
      for word in para:gmatch("%S+") do
        if cur == "" then
          cur = word
        elseif vim.fn.strdisplaywidth(cur .. " " .. word) <= width then
          cur = cur .. " " .. word
        else
          out[#out + 1] = cur
          cur = word
        end
      end
      if cur ~= "" then out[#out + 1] = cur end
    end
  end
  return out
end

-- Where to anchor a float. Default bottom-right (Clippy-style, out of the way).
-- config.position: "bottom-right" | "top-right" | "bottom-left" | "top-left" | "center"
local function place(ui, width, height, config)
  local m = 2 -- margin from edges
  local pos = (config and config.position) or "bottom-right"
  local bottom = math.max(0, ui.height - height - m - 1) -- -1 for cmdline
  local right = math.max(0, ui.width - width - m)
  local center_row = math.max(0, math.floor((ui.height - height) / 2))
  local center_col = math.max(0, math.floor((ui.width - width) / 2))

  if pos == "center" then
    return center_row, center_col
  elseif pos == "top-left" then
    return m, m
  elseif pos == "top-right" then
    return m, right
  elseif pos == "bottom-left" then
    return bottom, m
  else -- bottom-right
    return bottom, right
  end
end

-- ── matrix-style loading float ────────────────────────────────────────────
-- Returns { close = fn }. Animates until close() is called.
function M.loading(config, message)
  local ui = vim.api.nvim_list_uis()[1]
  if not ui then
    return { close = function() end }
  end

  local w = math.min(48, math.max(30, math.floor(ui.width * 0.4)))
  local h = 9
  local row, col = place(ui, w, h, config)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
    focusable = false,
    title = " sensei ",
    title_pos = "center",
  })

  pcall(vim.api.nvim_set_hl, 0, "SenseiMatrix", { fg = "#39ff14" })
  vim.api.nvim_win_set_option(win, "winhighlight", "Normal:SenseiMatrix,FloatBorder:SenseiMatrix")
  vim.api.nvim_win_set_option(win, "winblend", 5)

  local glyphs = {
    "0", "1", "ｱ", "ｲ", "ｳ", "ｴ", "ｵ", "ﾊ", "ﾋ", "ﾌ", "ﾅ", "ﾆ",
    "ﾇ", "ﾐ", "ﾑ", "ﾓ", "#", "$", "%", "&", "*", "+", "=", ":",
  }
  local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 0
  local closed = false

  local function rain_row()
    local cells = {}
    for _ = 1, w - 2 do
      cells[#cells + 1] = (math.random() < 0.45) and glyphs[math.random(#glyphs)] or " "
    end
    return " " .. table.concat(cells)
  end

  local timer = uv.new_timer()

  local function render()
    if closed or not vim.api.nvim_buf_is_valid(buf) then return end
    frame = frame + 1

    local lines = {}
    for _ = 1, h - 3 do
      lines[#lines + 1] = rain_row()
    end

    local msg = spinner[(frame % #spinner) + 1] .. "  " .. message
    local pad = math.max(0, math.floor((w - vim.fn.strdisplaywidth(msg)) / 2))
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.rep(" ", pad) .. msg

    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
  end

  timer:start(0, 90, vim.schedule_wrap(render))

  return {
    close = function()
      if closed then return end
      closed = true
      pcall(function()
        timer:stop()
        timer:close()
      end)
      pcall(vim.api.nvim_win_close, win, true)
    end,
  }
end

-- ── result window ─────────────────────────────────────────────────────────
-- We strip the binary's box and re-wrap to our own (narrower) width, then draw
-- our own rounded border anchored bottom-right. Long output scrolls (j/k/<C-d>).
function M.open(lines, config, dismiss_timeout)
  local text, title = unbox(strip_ansi(lines))

  local inner_w = math.max(20, config.width or 44) -- text column width
  text = wrap_text(text, inner_w)
  if not has_content(text) then text = { "(nothing to show)" } end

  -- pad each line to inner_w so the float doesn't hug the text edge
  local padded = {}
  for _, l in ipairs(text) do
    padded[#padded + 1] = " " .. l
  end

  local width = inner_w + 2
  local max_h = config.max_height or 18
  local height = math.min(#padded, max_h)

  -- dismiss_timeout == 0  → persistent: focus the float, close only on q/Esc/
  --                        clicking away (BufLeave). Used for context tip,
  --                        explain, ask, manual :SenseiTip.
  -- dismiss_timeout > 0   → ephemeral: unfocused, auto-close on cursor move
  --                        or after the timeout. Used for the ambient VimEnter
  --                        tip so startup noise doesn't linger.
  local persistent = (dismiss_timeout or 0) == 0

  local ui = vim.api.nvim_list_uis()[1]
  if not ui then return end
  local row, col = place(ui, width + 2, height + 2, config) -- +2 for border

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  local win = vim.api.nvim_open_win(buf, persistent, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title or " sensei ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(win, "winblend", 0) -- opaque: readable over code
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "winhighlight", "Normal:NormalFloat,FloatBorder:NormalFloat")

  local function close()
    pcall(vim.api.nvim_win_close, win, true)
  end

  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })

  if persistent then
    -- focused; close when the user navigates away (click in another window, :q, etc.)
    vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = close })
  else
    local group = vim.api.nvim_create_augroup("SenseiWindow" .. win, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
      group = group,
      callback = function()
        close()
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end,
      once = true,
    })
    vim.defer_fn(close, dismiss_timeout)
  end
end

-- ── async runner: loader → job → result/error ─────────────────────────────
local function run_async(config, args, message, on_done)
  local loader = M.loading(config, message)
  local stdout, stderr = {}, {}

  local job = vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d) stdout = d end,
    on_stderr = function(_, d) stderr = d end,
    on_exit = function(_, code)
      vim.schedule(function()
        loader.close()
        on_done(code, stdout, stderr)
      end)
    end,
  })

  if job <= 0 then
    loader.close()
    on_done(-1, {}, { "could not start '" .. args[1] .. "' — is it on PATH? (:SenseiHealth)" })
  end
end

-- Run an Ollama-backed command with the loader, then show result or error.
function M.run_and_show(config, args, label, dismiss, message)
  run_async(config, args, message or "sensei thinking…", function(code, stdout, stderr)
    local err = vim.trim(table.concat(stderr or {}, " "))

    if code ~= 0 then
      M.open({
        "⚠  sensei: " .. label:lower() .. " failed",
        "",
        err ~= "" and err or ("exit code " .. code),
        "",
        "Try :SenseiHealth — is Ollama running?",
      }, config, 0)
      return
    end

    local lines = strip_ansi(stdout or {})
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    if not has_content(lines) then
      lines = { "(sensei returned nothing)" }
    end

    -- Binary exits 0 but warns on stderr when it fell back to a static tip.
    if err:find("Ollama unavailable") then
      table.insert(lines, 1, "")
      table.insert(lines, 1, "⚠  Ollama unavailable — static tip shown. :SenseiHealth")
    end

    M.open(lines, config, dismiss)
  end)
end

-- ── public entry points ───────────────────────────────────────────────────
-- topic ~= nil  -> static tip (instant, offline, no loader)
-- context==true -> context-aware AI tip (async + loader)
function M.show_tip(config, topic, context)
  local args = { config.binary, "tip" }

  -- explicit topic via :SenseiTip <topic> — user asked for it, keep on screen
  if topic and topic ~= "" then
    vim.list_extend(args, { "--topic", topic })
    local out = vim.fn.systemlist(args) -- static: instant
    if vim.v.shell_error == 0 then
      M.open(out, config, 0) -- persistent: q/Esc/click-away to close
    end
    return
  end

  -- context-aware tip via <leader>kt — user pressed a key, keep on screen
  if context then
    vim.list_extend(args, {
      "--lang", vim.bo.filetype,
      "--mode", vim.api.nvim_get_mode().mode,
      "--line", vim.api.nvim_get_current_line(),
    })
    M.run_and_show(config, args, "TIP", 0, "sensei finding a tip…") -- persistent
    return
  end

  -- ambient VimEnter tip: ephemeral so startup noise doesn't linger
  local out = vim.fn.systemlist(args)
  if vim.v.shell_error == 0 then
    M.open(out, config, config.dismiss_timeout)
  end
end

function M.show_explain(config, text)
  M.run_and_show(config, { config.binary, "explain", text }, "EXPLAIN", 0, "sensei explaining…")
end

function M.show_ask(config, question)
  M.run_and_show(config, { config.binary, "ask", question }, "SENSEI", 0, "sensei thinking…")
end

return M
