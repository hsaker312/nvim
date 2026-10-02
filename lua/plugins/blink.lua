-- return {
--     "saghen/blink.cmp",
--     dependencies = "rafamadriz/friendly-snippets",
--
--     opts = {
--         completion = {
--             menu = { border = "rounded" },
--             documentation = { window = { border = "rounded" } },
--             ghost_text = { enabled = false },
--             trigger = { prefetch_on_insert = false },
--         },
--         keymap = {
--             ["<tab>"] = { "hide", "fallback" },
--             ["<C-n>"] = {
--                 "snippet_forward",
--                 "fallback",
--             },
--             ["<C-.>"] = {
--                 "snippet_backward",
--                 "fallback",
--             },
--         },
--         sources = {
--             -- Enable minuet for autocomplete
--             default = { "lsp", "path", "buffer", "snippets" },
--             -- For manual completion only, remove 'minuet' from default
--             providers = {
--                 -- minuet = {
--                 --     name = "minuet",
--                 --     module = "minuet.blink",
--                 --     async = true,
--                 --     -- Should match minuet.config.request_timeout * 1000,
--                 --     -- since minuet.config.request_timeout is in seconds
--                 --     timeout_ms = 3000,
--                 --     score_offset = 50, -- Gives minuet higher priority among suggestions
--                 -- },
--             },
--         },
--     },
-- }

return {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
        opts.completion = opts.completion or {}
        opts.completion.menu = opts.completion.menu or {}
        opts.completion.ghost_text = opts.completion.ghost_text or {}

        local inherited_auto_show = opts.completion.menu.auto_show

        opts.completion.menu.auto_show = function(ctx, items)
            if vim.bo[ctx.bufnr].filetype == "opencode" then
                -- Do not auto-open while writing prose; explicit Blink triggers still open it.
                return ctx.trigger.kind == "trigger_character"
            end

            if type(inherited_auto_show) == "function" then
                return inherited_auto_show(ctx, items)
            end
            return inherited_auto_show ~= false
        end

        opts.completion.menu.border = "rounded"
        opts.completion.documentation.window = { border = "rounded" }
        opts.completion.trigger = { prefetch_on_insert = false }
        opts.completion.ghost_text.enabled = false

        opts.keymap = {
            ["<cr>"] = { "accept", "fallback" },
            ["<tab>"] = { "hide", "fallback" },
            ["<C-.>"] = {
                "snippet_forward",
            },
            ["<C-,>"] = {
                "snippet_backward",
            },
        }

        return opts
    end,
}
