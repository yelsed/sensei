local window = require("sensei.window")

local M = {}

function M.setup(config)
  local km = config.keymaps

  -- manual tip
  vim.keymap.set("n", km.tip, function()
    window.show_tip(config, nil)
  end, { desc = "Sensei: random tip" })

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

  -- ask a question
  vim.keymap.set("n", km.ask, function()
    vim.ui.input({ prompt = "Sensei > " }, function(input)
      if input and input ~= "" then
        window.show_ask(config, input)
      end
    end)
  end, { desc = "Sensei: ask a question" })

  -- ambient tip on VimEnter
  if config.auto_tip then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("SenseiAutoTip", { clear = true }),
      callback = function()
        vim.defer_fn(function()
          window.show_tip(config, nil)
        end, config.auto_tip_delay)
      end,
      once = true,
    })
  end

  -- user commands
  vim.api.nvim_create_user_command("SenseiTip", function(opts)
    window.show_tip(config, opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Show a sensei tip" })

  vim.api.nvim_create_user_command("SenseiAsk", function(opts)
    window.show_ask(config, opts.args)
  end, { nargs = "+", desc = "Ask sensei a question" })

  vim.api.nvim_create_user_command("SenseiExplain", function(opts)
    window.show_explain(config, opts.args)
  end, { nargs = "+", desc = "Ask sensei to explain something" })
end

return M
