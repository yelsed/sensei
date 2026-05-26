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

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  require("sensei.commands").setup(M.config)
end

return M
