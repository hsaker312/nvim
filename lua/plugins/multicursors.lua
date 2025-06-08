return {
    "smoka7/multicursors.nvim",
    enabled = not vim.g.lite,
    event = "VeryLazy",
    dependencies = {
        "smoka7/hydra.nvim",
    },
    -- opts = {},
    cmd = { "MCstart", "MCvisual", "MCclear", "MCpattern", "MCvisualPattern", "MCunderCursor" },
}
