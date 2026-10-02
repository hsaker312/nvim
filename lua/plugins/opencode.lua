return {
    "sudo-tee/opencode.nvim",
    dependencies = {
        "MeanderingProgrammer/render-markdown.nvim",
    },
    config = function()
        require("opencode").setup({
            -- 'telescope', 'fzf-lua', 'snacks', etc. (auto-detects if nil)
            preferred_picker = "fzf-lua",
            preferred_completion = "blink",

            keymap_prefix = "<leader>o",

            opencode_executable = "opencode",

            ui = {
                completion = {
                    file_sources = {
                        enabled = true,
                        preferred_cli_tool = "server", -- 'fd','fdfind','rg','git','server' if nil, it will use the best available tool, 'server' uses opencode cli to get file list (works cross platform) and supports folders
                        ignore_patterns = {
                            "^%.git/",
                            "^%.svn/",
                            "^%.hg/",
                            "node_modules/",
                            "%.pyc$",
                            "%.o$",
                            "%.obj$",
                            "%.exe$",
                            "%.dll$",
                            "%.so$",
                            "%.dylib$",
                            "%.class$",
                            "%.jar$",
                            "%.war$",
                            "%.ear$",
                            "target/",
                            "build/",
                            "dist/",
                            "out/",
                            "deps/",
                            "%.tmp$",
                            "%.temp$",
                            "%.log$",
                            "%.cache$",
                        },
                        max_files = 10,
                        max_display_length = 50, -- Maximum length for file path display in completion, truncates from left with "..."
                    },
                },
            },
        })
    end,
}
