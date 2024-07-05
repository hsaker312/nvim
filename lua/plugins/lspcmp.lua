return {
    "hrsh7th/nvim-cmp",
    dependencies = {
        "L3MON4D3/LuaSnip",
    },
    opts = function(_, opts)
        local cmp = require("cmp")
        local luasnip = require("luasnip")

        opts.mapping = cmp.mapping.preset.insert({
            ["<C-b>"] = cmp.mapping.scroll_docs(-4),
            ["<C-f>"] = cmp.mapping.scroll_docs(4),
            ["<C-Space>"] = cmp.mapping.complete(),
            ["<esc>"] = cmp.mapping.abort(),
            ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
            ["<Tab>"] = cmp.mapping(function()
                vim.api.nvim_command("normal! i\t")
                vim.api.nvim_command("normal! l")
            end),
            ["<S-Tab>"] = cmp.mapping(function()
                local line_num = vim.fn.line(".")
                local col_num = vim.fn.col(".")
                local line = vim.fn.getline(line_num)

                vim.api.nvim_command("normal! v<")
                if col_num < #line then
                    vim.api.nvim_command("normal! hhhh")
                end
            end),
            ["<A-n>"] = cmp.mapping(function(fallback)
                if cmp.visible() then
                    cmp.select_next_item()
                elseif luasnip.expandable() then
                    luasnip.expand()
                elseif luasnip.expand_or_jumpable() then
                    luasnip.expand_or_jump()
                else
                    fallback()
                end
            end, {
                "i",
                "s",
            }),
            ["<C-n>"] = cmp.mapping(function(fallback)
                if cmp.visible() then
                    cmp.select_prev_item()
                elseif luasnip.jumpable(-1) then
                    luasnip.jump(-1)
                else
                    fallback()
                end
            end, {
                "i",
                "s",
            }),
        })
        opts.window = {
            completion = cmp.config.window.bordered(),
            documentation = cmp.config.window.bordered(),
        }
        opts.experimental = {
            ghost_text = nil,
        }
    end,
}
