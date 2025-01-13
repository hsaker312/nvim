return {
    "gelguy/wilder.nvim",
    enabled = not vim.g.lite,
    config = function()
        local wilder = require("wilder")

        wilder.setup({ modes = { ":", "/", "?" } })

        wilder.set_option("pipeline", {
            wilder.branch(
                wilder.python_file_finder_pipeline({
                    -- to use ripgrep : {'rg', '--files'}
                    -- to use fd      : {'fd', '-tf'}
                    file_command = { "find", ".", "-type", "f", "-printf", "%P\n" },
                    -- to use fd      : {'fd', '-td'}
                    dir_command = { "find", ".", "-type", "d", "-printf", "%P\n" },
                    -- use {'cpsm_filter'} for performance, requires cpsm vim plugin
                    -- found at https://github.com/nixprime/cpsm
                    filters = { "fuzzy_filter", "difflib_sorter" },
                }),
                wilder.cmdline_pipeline(),
                wilder.python_search_pipeline()
            ),
        })

        local gradient = {
            "#f4468f",
            "#fd4a85",
            "#ff507a",
            "#ff566f",
            "#ff5e63",
            "#ff6658",
            "#ff704e",
            "#ff7a45",
            "#ff843d",
            "#ff9036",
            "#f89b31",
            "#efa72f",
            "#e6b32e",
            "#dcbe30",
            "#d2c934",
            "#c8d43a",
            "#bfde43",
            "#b6e84e",
            "#aff05b",
        }

        for i, fg in ipairs(gradient) do
            gradient[i] = wilder.make_hl("WilderGradient" .. i, "Pmenu", { { a = 1 }, { a = 1 }, { foreground = fg } })
        end

        wilder.set_option(
            "renderer",
            wilder.popupmenu_renderer({
                highlights = {
                    border = "Normal",
                    gradient = gradient, -- must be set
                    -- selected_gradient key can be set to apply gradient highlighting for the selected candidate.
                },
                highlighter = wilder.highlighter_with_gradient({
                    wilder.basic_highlighter(), -- or wilder.lua_fzy_highlighter(),
                }),
                border = "rounded",
            })
        )
    end,
}
