return {
  {
    "Bekaboo/dropbar.nvim",
    enabled = not vim.g.vscode,
    -- optional, but required for fuzzy finder support
    dependencies = {
      "nvim-telescope/telescope-fzf-native.nvim",
    },
    config = function()
      require("dropbar").setup({})
      vim.ui.select = require("dropbar.utils.menu").select
    end,
  },
}
