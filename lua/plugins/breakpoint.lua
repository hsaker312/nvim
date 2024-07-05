return {
  "Weissle/persistent-breakpoints.nvim",
  config = function()
    require("persistent-breakpoints").setup({
      save_dir = vim.loop.cwd() .. "/.nvim/breakpoints",
      load_breakpoints_event = { "BufReadPost" },
    })
  end,
}
