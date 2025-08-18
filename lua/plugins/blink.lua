return {
    "saghen/blink.cmp",
    dependencies = "rafamadriz/friendly-snippets",

    opts = {
        completion = {
            ghost_text = { enabled = false },
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
    },
}
