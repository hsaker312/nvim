return {
    "echasnovski/mini.nvim",
    version = "*",
    config = function()
        require("mini.ai").setup()
        require("mini.extra").setup()
        require("mini.pick").setup()
        require("mini.indentscope").setup()
    end,
}
