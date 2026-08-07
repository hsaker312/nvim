return {
    "taigrr/neocrush.nvim",
    enabled = false,
    branch = "v2-bridge",
    dependencies = { "nvim-telescope/telescope.nvim", "taigrr/glaze.nvim" },
    event = "VeryLazy",
    init = function()
        -- Register binaries with glaze for auto-install/update
        local glaze = require("glaze")
        glaze.register("crush", "github.com/taigrr/crush", { plugin = "neocrush.nvim" })
    end,
    opts = {
        -- All options are optional with sensible defaults
        highlight_group = "IncSearch", -- Flash highlight group
        highlight_duration = 900, -- Flash duration (ms)
        auto_focus = true, -- Auto-focus edited files
        terminal_width = 115, -- Terminal width in columns
        terminal_side = "right", -- Side to open the terminal ('right' or 'left')
        terminal_cmd = "~/go/bin/crush", -- Command to run in terminal

        -- CVM configuration (optional)
        cvm = {
            upstream = "taigrr/crush", -- GitHub repo for releases
            -- local_repo = '~/build/crush-repo',       -- Default path for :CrushCvmLocal
        },

        -- Optional keybindings (none set by default)
        keys = {
            toggle = "<leader>ccc",
            focus = "<leader>ccf",
            logs = "<leader>ccl",
            cancel = "<leader>ccx",
            restart = "<leader>ccr",
            paste = "<leader>ccp", -- Works in normal (clipboard) and visual (selection) mode
            cvm_releases = "<leader>ccvr",
            cvm_local = "<leader>ccvl",
        },
    },
}
