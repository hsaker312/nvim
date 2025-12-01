-- LSP Support
return {
    -- LSP Configuration
    -- https://github.com/neovim/nvim-lspconfig
    "neovim/nvim-lspconfig",
    enabled = not vim.g.lite,
    event = "VeryLazy",
    dependencies = {
        -- LSP Management
        { "mason-org/mason.nvim" },
        { "mason-org/mason-lspconfig.nvim" },

        -- Auto-Install LSPs, linters, formatters, debuggers
        -- https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim
        { "WhoIsSethDaniel/mason-tool-installer.nvim" },

        -- Useful status updates for LSP
        -- https://github.com/j-hui/fidget.nvim
        -- { "j-hui/fidget.nvim", opts = {} },

        -- Additional lua configuration, makes nvim stuff amazing!
        -- https://github.com/folke/neodev.nvim
        { "folke/neodev.nvim" },
    },
    config = function()
        require("mason").setup()
        require("mason-lspconfig").setup({
            automatic_enable = {
                exclude = { "jdtls", "clangd", "lua_ls" },
            },
            ensure_installed = {
                -- "jdtls",
                -- "jsonls",
                -- "pyright",
            },
        })

        require("mason-tool-installer").setup({
            -- Install these linters, formatters, debuggers automatically
            ensure_installed = {
                -- "asm-lsp",
                -- "asmfmt",
                -- "bash-language-server",
                -- "cmake-language-server",
                -- "lua-language-server",
                -- "black",
                -- "clang-format",
                -- "codelldb",
                -- "codespell",
                -- "cpptools",
                -- "debugpy",
                -- "java-debug-adapter",
                -- "java-test",
                -- "mypy",
                -- "ruff",
                -- "shfmt",
                -- "stylua",
                -- "vscode-java-decompiler",
                -- "xmlformatter",
            },
        })

        -- There is an issue with mason-tools-installer running with VeryLazy, since it triggers on VimEnter which has already occurred prior to this plugin loading so we need to call install explicitly
        -- https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim/issues/39
        vim.api.nvim_command("MasonToolsInstall")

        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities.textDocument.completion.completionItem.snippetSupport = true

        -- require("lspconfig").jsonls.setup({})
        -- require("lspconfig").bashls.setup({})
        if require("lspconfig").pyright then
            require("lspconfig").pyright.setup({})
        end

        if require("lspconfig").ruff then
            require("lspconfig").ruff.setup({})
        end

        if require("lspconfig").cmake then
            require("lspconfig").cmake.setup({})
        end

        if require("lspconfig").nim_langserver then
            require("lspconfig").nim_langserver.setup({})
        end

        if require("lspconfig").omnisharp then
            require("lspconfig").omnisharp.setup({})
        end

        if require("lspconfig").ts_ls then
            require("lspconfig").ts_ls.setup({})
        end

        if require("lspconfig").lua_ls then
            require("lspconfig").lua_ls.setup({
                settings = {
                    Lua = {
                        diagnostics = {
                            -- Get the language server to recognize the `vim` global
                            globals = { "vim" },
                        },
                    },
                },
            })
        end

        local lsp_capabilities = require("blink-cmp").get_lsp_capabilities({}, true)
        local lsp_attach = function(client, bufnr)
            -- Create your keybindings here...
        end

        -- -- Call setup on each LSP server
        -- require("mason-lspconfig").setup_handlers({
        --     function(server_name)
        --         -- Don't call setup for JDTLS Java LSP because it will be setup from a separate config
        --         if server_name ~= "jdtls" then
        --             lspconfig[server_name].setup({
        --                 on_attach = lsp_attach,
        --                 capabilities = lsp_capabilities,
        --             })
        --         end
        --     end,
        -- })

        -- Globally configure all LSP floating preview popups (like hover, signature help, etc)
        -- local open_floating_preview = vim.lsp.util.open_floating_preview
        --
        -- function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
        --     opts = opts or {}
        --     opts.border = opts.border or "rounded" -- Set border to rounded
        --     return open_floating_preview(contents, syntax, opts, ...)
        -- end
    end,
}
