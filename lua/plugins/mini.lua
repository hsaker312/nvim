return {
    "echasnovski/mini.nvim",
    version = "*",
    config = function()
        require("mini.ai").setup()
        require("mini.extra").setup()
        if not vim.g.lite then
            require("mini.pick").setup()
            require("mini.indentscope").setup()
        end
    end,
}
