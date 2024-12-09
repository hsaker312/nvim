return {
    "stevearc/conform.nvim",
    opts = {
        formatters_by_ft = {
            lua = { "stylua" },
            cpp = { "clang_format" },
            xml = { "xmlformatter" },
            asm = { "asmfmt" },
            json = { "fixjson" },
            python = { "black" },
            -- ["*"] = { "codespell" },
        },
    },
}
