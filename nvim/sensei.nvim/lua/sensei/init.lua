local M = {}

M.config = {
  binary = "sensei",
  width = 54,
  auto_tip = true,
  auto_tip_delay = 500,  -- ms before showing on VimEnter
  dismiss_timeout = 8000, -- ms before auto-close (0 = never)
  keymaps = {
    tip = "<leader>st",
    explain = "<leader>se",
    ask = "<leader>sa",
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  require("sensei.commands").setup(M.config)
end

return M
