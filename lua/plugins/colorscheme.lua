-- return {
--   {
--     "folke/tokyonight.nvim",
--     opts = {
--       style = "storm",
--       transparent = true,
--       styles = {
--         sidebars = "transparent",
--         floats = "transparent",
--       },
--     },
--   },
-- }
--
return {
    "catppuccin/nvim",
    name = "catppuccin",
    enabled = not vim.g.lite,
    priority = 1000,
    opts = {
        transparent_background = true,
        float = {
            transparent = true, -- enable transparent floating windows
            solid = false, -- use solid styling for floating windows, see |winborder|
        },
        term_colors = false,
        integrations = {
            telescope = true,
            mason = true,
            neotree = true,
            gitsigns = true,
            noice = true,
            notifier = true,
            notify = true,
            rainbow_delimiters = true,
            lsp_trouble = true,
            which_key = true,
            dropbar = {
                enabled = true,
                color_mode = true, -- enable color for kind's texts, not just kind's icons
            },
            native_lsp = {
                enabled = true,
                virtual_text = {
                    errors = {},
                    hints = {},
                    warnings = {},
                    information = {},
                },
                underlines = {
                    errors = { "undercurl" },
                    hints = { "undercurl" },
                    warnings = { "undercurl" },
                    information = { "undercurl" },
                },
            },
        },
    },
}
