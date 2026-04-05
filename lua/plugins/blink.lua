return {
    "saghen/blink.cmp",
    dependencies = "rafamadriz/friendly-snippets",

    opts = {
        completion = {
            menu = { border = "rounded" },
            documentation = { window = { border = "rounded" } },
            ghost_text = { enabled = false },
            trigger = { prefetch_on_insert = false },
        },
        keymap = {
            ["<tab>"] = { "hide", "fallback" },
            ["<C-n>"] = {
                "snippet_forward",
                "fallback",
            },
            ["<C-.>"] = {
                "snippet_backward",
                "fallback",
            },
        },
        sources = {
            -- Enable minuet for autocomplete
            default = { "lsp", "path", "buffer", "snippets", "minuet" },
            -- For manual completion only, remove 'minuet' from default
            providers = {
                minuet = {
                    name = "minuet",
                    module = "minuet.blink",
                    async = true,
                    -- Should match minuet.config.request_timeout * 1000,
                    -- since minuet.config.request_timeout is in seconds
                    timeout_ms = 3000,
                    score_offset = 50, -- Gives minuet higher priority among suggestions
                },
            },
        },
    },
}
