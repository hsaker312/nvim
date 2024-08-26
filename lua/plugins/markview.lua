return {
    "OXY2DEV/markview.nvim",
    enabled = not vim.g.vscode,
    dependencies = {
        -- You may not need this if you don't lazy load
        -- Or if the parsers are in your $RUNTIMEPATH
        "nvim-treesitter/nvim-treesitter",

        "nvim-tree/nvim-web-devicons"
    },
}
