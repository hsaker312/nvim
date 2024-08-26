return {
    "mfussenegger/nvim-lint",
    enabled = not vim.g.vscode,
    config = function()
        require("lint").linters_by_ft = {
            python = { "mypy", "ruff" },
        }
    end,
}
