return {
    "mfussenegger/nvim-lint",
    config = function()
        require("lint").linters_by_ft = {
            python = {"mypy", "ruff",}
        }
    end
}
