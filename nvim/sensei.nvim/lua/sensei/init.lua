local M = {}

M.config = {
  binary = "sensei",
  width = 44,              -- inner text width (smaller = narrower popup)
  max_height = 18,         -- taller output scrolls (j/k/<C-d>, q to close)
  position = "bottom-right", -- bottom-right|top-right|bottom-left|top-left|center
  auto_tip = true,
  auto_tip_delay = 500,  -- ms before showing on VimEnter
  dismiss_timeout = 8000, -- ms before auto-close (0 = never)
  keymaps = {
    tip = "<leader>st",     -- context-aware tip
    explain = "<leader>se", -- explain line/selection
    ask = "<leader>sa",     -- open chat (follow-up Q&A)
    health = "<leader>sh",  -- health check
  },
}

local function set_hl_defaults()
  local hl = function(name, opts)
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, opts))
  end
  hl("SenseiYou", { link = "Function" })
  hl("SenseiSensei", { link = "Identifier" })
  hl("SenseiArrow", { link = "Comment" })
  hl("SenseiHint", { link = "Comment" })
  hl("SenseiThinking", { fg = "#39ff14" })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  set_hl_defaults()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl_defaults })
  require("sensei.commands").setup(M.config)
end

return M
