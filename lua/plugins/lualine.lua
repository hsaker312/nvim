return {
    "nvim-lualine/lualine.nvim",
    -- enabled = not vim.g.lite,
    dependencies = { "linux-cultist/venv-selector.nvim", "Civitasv/cmake-tools.nvim", "arkav/lualine-lsp-progress" },
    event = "VeryLazy",
    opts = {
        sections = {
            lualine_c = {
                {
                    function()
                        local recording_register = vim.fn.reg_recording()
                        if recording_register == "" then
                            return ""
                        else
                            return "Recording @" .. recording_register
                        end
                    end,
                },
            },
            lualine_z = {
                {
                    function()
                        local starts = vim.fn.line("v")
                        local ends = vim.fn.line(".")
                        local lines = starts <= ends and ends - starts + 1 or starts - ends + 1
                        return tostring(lines)
                            .. "L "
                            .. tostring(vim.fn.wordcount().visual_words)
                            .. "W "
                            .. tostring(vim.fn.wordcount().visual_chars)
                            .. "C"
                    end,
                    cond = function()
                        return vim.fn.mode():find("[Vv]") ~= nil
                    end,
                },
            },
            lualine_x = {
                {
                    "lsp_progress",
                    fmt = function(str)
                        str = str:gsub("%%", "󰏰"):gsub("󰏰󰏰", "󰏰")
                        -- print(str)
                        if #str > 70 then
                            return str:sub(1, 70) .. "..."
                        else
                            return str
                        end
                    end,
                    display_components = { "lsp_client_name", "spinner", { "percentage", "message", "title" } },
                    timer = { progress_enddelay = 500, spinner = 500, lsp_client_name_enddelay = -1 },
                    separators = {
                        component = " ",
                        progress = " ",
                        title = { pre = " ", post = " " },
                        lsp_client_name = { pre = "[", post = "]" },
                        spinner = { pre = " ", post = " " },
                        message = { commenced = "", completed = "" },
                    },
                    separator = { left = "", right = "" },
                    color = { fg = "#FFFFFF", bg = "#3f2a54", gui = "bold" },
                    spinner_symbols = { "", "", "", "", "", "" },
                },
                {
                    function()
                        return " "
                    end,
                },
                {
                    function()
                        local venv_name = require("venv-selector").get_active_venv()
                        if venv_name ~= nil then
                            return " "
                                .. venv_name
                                    :gsub(".*/pypoetry/virtualenvs/", "(poetry) ")
                                    :gsub(".*\\pypoetry\\virtualenvs\\", "(poetry) ")
                                    :gsub(vim.loop.cwd() .. "/", "")
                        else
                            return " " .. "Select Venv"
                        end
                    end,
                    color = { fg = "#bdb480", bg = "#405f6b", gui = "italic,bold" },
                    separator = { left = "" },
                    cond = function()
                        return vim.bo.filetype == "python"
                    end,
                    on_click = function()
                        vim.cmd.VenvSelect()
                    end,
                },
                {
                    function()
                        local targetPath = ""

                        if package.cpath:match("%p[\\|/]?%p(%a+)") == "so" then
                            targetPath = vim.loop.cwd() .. "/.nvim/dap.linux.target"
                        else
                            targetPath = vim.loop.cwd() .. "/.nvim/dap.win.target"
                        end

                        local file = io.open(targetPath, "r")

                        if file ~= nil then
                            local target = file:read("*a")
                            file:close()
                            return "󱓟 " .. target:gsub(vim.loop.cwd() .. "/", ""):gsub(vim.loop.cwd() .. "\\", "")
                        else
                            return " "
                        end

                        return ""
                    end,
                    color = { fg = "#bdb480", bg = "#405f6b", gui = "italic,bold" },
                    -- separator = { right = " " },
                    separator = { right = "" },
                    cond = function()
                        return vim.bo.filetype == "python"
                    end,
                    on_click = function()
                        local targetPath = ""

                        if package.cpath:match("%p[\\|/]?%p(%a+)") == "so" then
                            targetPath = vim.loop.cwd() .. "/.nvim/dap.linux.target"
                        else
                            targetPath = vim.loop.cwd() .. "/.nvim/dap.win.target"
                        end

                        local file = io.open(targetPath, "w")

                        if file ~= nil then
                            file:write("")
                            file:close()
                        end
                    end,
                },
                {
                    function()
                        return " "
                    end,
                    cond = function()
                        return vim.bo.filetype == "python"
                    end,
                },
                {
                    function()
                        return "󰣪 "
                    end,
                    separator = { left = "" },
                    color = { fg = "#000000", bg = "#79a2ad", gui = "bold" },
                    cond = function()
                        return require("cmake-tools").get_configure_preset() ~= nil
                    end,
                    on_click = function()
                        vim.api.nvim_command("CMakeBuild")
                    end,
                },
                {
                    function()
                        return " " .. require("cmake-tools").get_configure_preset()
                    end,
                    -- separator = { left = "" },
                    color = { fg = "#FFFFFF", bg = "#565f87", gui = "bold" },
                    cond = function()
                        return require("cmake-tools").get_configure_preset() ~= nil
                    end,
                    on_click = function()
                        vim.api.nvim_command("CMakeSelectConfigurePreset")
                    end,
                },
                {
                    function()
                        if require("cmake-tools").get_launch_target() ~= require("cmake-tools").get_build_target() then
                            return "󱥉 " .. require("cmake-tools").get_build_target()
                        else
                            return "󱥉"
                        end
                    end,
                    color = { fg = "#FFFFFF", bg = "#63436e", gui = "bold" },
                    cond = function()
                        return require("cmake-tools").get_configure_preset() ~= nil
                    end,
                    separator = { right = "" },
                    on_click = function()
                        vim.api.nvim_command("CMakeSelectBuildTarget")
                    end,
                },
                -- {
                --     function()
                --         return "󱓟 " .. require("cmake-tools").get_launch_target()
                --     end,
                --     separator = { right = "" },
                --     color = { fg = "#FFFFFF", bg = "#6e4359", gui = "bold" },
                --     cond = function()
                --         return require("cmake-tools").get_configure_preset() ~= nil
                --     end,
                --     on_click = function()
                --         vim.api.nvim_command("CMakeSelectLaunchTarget")
                --     end,
                -- },
                {
                    function()
                        return " "
                    end,
                    cond = function()
                        return require("cmake-tools").get_configure_preset() ~= nil
                    end,
                },
                {
                    function()
                        return " "
                    end,
                    separator = { left = "", right = "" },
                    color = { fg = "#000000", bg = "#5b8076", gui = "bold" },
                    on_click = function()
                        if require("cmake-tools").get_configure_preset() ~= nil then
                            vim.api.nvim_command("CMakeDebug")
                        else
                            if vim.bo.filetype == "java" then
                                require("jdtls.dap").setup_dap_main_class_configs()
                            end

                            vim.defer_fn(function()
                                vim.api.nvim_command("DapContinue")
                            end, 100)
                        end
                    end,
                },
                {
                    function()
                        return "󱕷 "
                    end,
                    separator = { left = "", right = "" },
                    color = { fg = "#000000", bg = "#5b8076", gui = "bold" },
                    on_click = function()
                        require("dapui").toggle()
                    end,
                },
                {
                    function()
                        return " "
                    end,
                },
            },
        },
    },
}
