return {
    "smoka7/multicursors.nvim",
    enabled = not vim.g.vscode,
    event = "VeryLazy",
    dependencies = {
        "smoka7/hydra.nvim",
    },
    opts = {},
    cmd = { "MCstart", "MCvisual", "MCclear", "MCpattern", "MCvisualPattern", "MCunderCursor" },
}
