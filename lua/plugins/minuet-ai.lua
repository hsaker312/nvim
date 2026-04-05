return {
    {
        "milanglacier/minuet-ai.nvim",
        config = function()
            require("minuet").setup({
                provider = 'gemini',
                provider_options = {
                    gemini = {
                        model = "gemini-2.5-flash",
                        stream = true,
                        api_key = "GEMINI_API_KEY",
                        end_point = "https://generativelanguage.googleapis.com/v1beta/models",
                        optional = {},
                        -- a list of functions to transform the endpoint, header, and request body
                        transform = {},
                    },
                },
            })
        end,
    },
    { "nvim-lua/plenary.nvim" },
    -- optional, if you are using virtual-text frontend, nvim-cmp is not
    -- required.
    { "hrsh7th/nvim-cmp" },
    -- optional, if you are using virtual-text frontend, blink is not required.
    { "Saghen/blink.cmp" },
}
