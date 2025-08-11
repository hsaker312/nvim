return {
    "stevearc/conform.nvim",
    opts = {
        formatters_by_ft = {
            lua = { "stylua" },
            c = { "clang_format" },
            cpp = { "clang_format" },
            xml = { "xmlformatter" },
            asm = { "asmfmt" },
            json = { "fixjson" },
            python = { "black" },
            cmake = {"gersemi"},
            javascript = {"prettier"}
            -- ["*"] = { "codespell" },
        },
    },
}
