return {
    "rcarriga/nvim-dap-ui",
    enabled = not vim.g.lite,
    dependencies = {
        "mfussenegger/nvim-dap",
        "nvim-neotest/nvim-nio",
    },

    config = function()
        local dap, dapui = require("dap"), require("dapui")
        dapui.setup()
        dap.listeners.before.attach.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.launch.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.event_terminated.dapui_config = function()
            dapui.close()
        end
        dap.listeners.before.event_exited.dapui_config = function()
            dapui.close()
        end
        -- vim.fn.sign_define(
        --     "DapBreakpoint",
        --     { text = "🔴", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
        -- )
        -- vim.fn.sign_define("DapBreakpoint", { text = " ", texthl = "red", linehl = "", numhl = "" })
        -- vim.fn.sign_define(
        --     "DapStopped",
        --     { text = "⏸️", texthl = "DapStopped", linehl = "DapStopped", numhl = "DapStopped" }
        -- )

        vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#db5427" })
        vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#db5427" })
        vim.api.nvim_set_hl(0, "DapStopped", { bg = "#211414" })

        vim.fn.sign_define(
            "DapBreakpoint",
            { text = " ", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
        )
        vim.fn.sign_define(
            "DapBreakpointCondition",
            { text = " ", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
        )
        vim.fn.sign_define(
            "DapBreakpointRejected",
            { text = " ", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
        )
        vim.fn.sign_define(
            "DapLogPoint",
            { text = " ", texthl = "DapLogPoint", linehl = "DapLogPoint", numhl = "DapLogPoint" }
        )
        vim.fn.sign_define(
            "DapStopped",
            { text = " ", texthl = "DapStopped", linehl = "DapStopped", numhl = "DapStopped" }
        )
    end,
}
