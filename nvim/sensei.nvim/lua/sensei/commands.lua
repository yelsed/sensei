local window = require("sensei.window")
local chat = require("sensei.chat")
local health = require("sensei.health")

local M = {}

function M.setup(config)
  local km = config.keymaps

  -- context-aware tip (looks at the current buffer/mode/line)
  vim.keymap.set("n", km.tip, function()
    window.show_tip(config, nil, true)
  end, { desc = "Sensei: context-aware tip" })

  -- explain current line (normal mode) or selection (visual mode)
  vim.keymap.set("n", km.explain, function()
    local line = vim.api.nvim_get_current_line()
    window.show_explain(config, line)
  end, { desc = "Sensei: explain current line" })

  vim.keymap.set("v", km.explain, function()
    -- exit visual, then get the last selection
    vim.cmd('normal! "vy')
    local text = vim.fn.getreg("v")
    window.show_explain(config, text)
  end, { desc = "Sensei: explain selection" })

  -- ask -> open the follow-up chat buffer
  vim.keymap.set("n", km.ask, function()
    chat.ask(config)
  end, { desc = "Sensei: chat / ask a question" })

  -- health check
  if km.health then
    vim.keymap.set("n", km.health, function()
      health.run(config)
    end, { desc = "Sensei: health check" })
  end

  -- ambient tip on VimEnter (static, so startup stays instant)
  if config.auto_tip then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("SenseiAutoTip", { clear = true }),
      callback = function()
        vim.defer_fn(function()
          window.show_tip(config, nil, false)
        end, config.auto_tip_delay)
      end,
      once = true,
    })
  end

  -- user commands
  vim.api.nvim_create_user_command("SenseiTip", function(opts)
    if opts.args ~= "" then
      window.show_tip(config, opts.args, false) -- static tip for a topic
    else
      window.show_tip(config, nil, true) -- context-aware
    end
  end, { nargs = "?", desc = "Show a sensei tip" })

  vim.api.nvim_create_user_command("SenseiAsk", function(opts)
    window.show_ask(config, opts.args) -- quick one-shot answer
  end, { nargs = "+", desc = "Ask sensei a one-shot question" })

  vim.api.nvim_create_user_command("SenseiChat", function()
    chat.ask(config) -- open the follow-up chat buffer
  end, { desc = "Open the sensei chat buffer" })

  vim.api.nvim_create_user_command("SenseiChatReset", function()
    chat.reset()
  end, { desc = "Clear the sensei chat history" })

  vim.api.nvim_create_user_command("SenseiExplain", function(opts)
    window.show_explain(config, opts.args)
  end, { nargs = "+", desc = "Ask sensei to explain something" })

  vim.api.nvim_create_user_command("SenseiHealth", function()
    health.run(config)
  end, { desc = "Check sensei binary + Ollama status" })
end

return M
