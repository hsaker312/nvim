-- if io.open(vim.loop.cwd() .. "/.nvim/.session", "r") ~= nil then
--   pcall(function()
--     vim.api.nvim_command("source " .. vim.loop.cwd() .. "/.nvim/.session")
--   end)
-- end
--

if vim.g.vscode then
    local vscode, _ = pcall(require, "vscode")

    if vscode ~= nil then
        vim.notify = vscode.notify
    end
else
    vim.notify = require("snacks").notify
end

vim.opt.incsearch = true
vim.opt.hlsearch = false

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.nu = true
vim.opt.rnu = false --disable relative line number


vim.opt.spelllang = "en_us"
vim.opt.spell = true

vim.opt.termguicolors = true

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = vim.env.HOME .. "/.nvim/undodir"
vim.opt.undofile = true

if not vim.g.lite then
    vim.api.nvim_create_user_command("EnableCMake", require("config.cmake").setup, {})

    local codelldb_path = require("mason-registry").get_package("codelldb"):get_install_path() .. "/extension"
    local codelldb_bin = codelldb_path .. "/adapter/codelldb"

    local dap = require("dap")

    local dap_run = dap.run

    local dap_run_fix = function(config, opts)
        if type(config.program) == "string" then
            local _, count = config.program:gsub("[A-Z]:[/,\\]", "")

            if count < 2 then
                return dap_run(config, opts)
            else
                local exe = config.program:gmatch(".+([A-Z]:[/,\\].+%.exe).*")
                local exePath = exe()

                if exePath ~= nil then
                    config.program = exePath

                    return dap_run(config, opts)
                else
                    print('Invalid Executable: "' .. config.program('"'))
                end
            end
        else
            return dap_run(config, opts)
        end
    end

    dap.run = dap_run_fix

    dap.adapters.codelldb = {
        name = "codelldb server",
        type = "server",
        port = "13000",
        executable = {
            command = codelldb_bin,
            args = { "--port", "13000" },
        },
    }

    dap.adapters.lldb_mi = {
        type = "executable",
        command = "/usr/bin/lldb-mi", -- Replace with the path to lldb-mi
        name = "lldb-mi",
    }

    dap.adapters.python = function(cb, config)
        if config.request == "attach" then
            ---@diagnostic disable-next-line: undefined-field
            local port = (config.connect or config).port
            ---@diagnostic disable-next-line: undefined-field
            local host = (config.connect or config).host or "127.0.0.1"
            cb({
                type = "server",
                port = assert(port, "`connect.port` is required for a python `attach` configuration"),
                host = host,
                options = {
                    source_filetype = "python",
                },
            })
        else
            cb({
                type = "executable",
                command = "python",
                args = { "-m", "debugpy.adapter" },
                options = {
                    source_filetype = "python",
                },
            })
        end
    end

    local dap_target = function()
        if package.cpath:match("%p[\\|/]?%p(%a+)") == "so" then
            return vim.loop.cwd() .. "/.nvim/dap.linux.target"
        else
            return vim.loop.cwd() .. "/.nvim/dap.win.target"
        end
    end

    dap.configurations.python = {
        {
            -- The first three options are required by nvim-dap
            type = "python", -- the type here established the link to the adapter definition: `dap.adapters.python`
            request = "launch",
            name = "Launch file",

            -- Options below are for debugpy, see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options

            program = function()
                local targetPath = dap_target()
                local file = io.open(targetPath, "r")

                if file ~= nil then
                    local target = file:read("*a")
                    file:close()
                    if #target > 0 then
                        return target
                    end
                end

                file = io.open(targetPath, "w")
                if file ~= nil then
                    file:write(vim.api.nvim_buf_get_name(0))
                    file:close()
                end

                return vim.api.nvim_buf_get_name(0)
            end, -- This configuration will launch the current file if used.
            pythonPath = function()
                return require("venv-selector").get_active_path()
            end,
        },
    }

    vim.lsp.log_level = vim.log.levels.ERROR

    require("conform").formatters.xmlformatter = function(bufnr)
        local home = vim.env.HOME

        if vim.g.windows then
            return {
                command = require("conform.util").find_executable({
                    home .. "/AppData/Local/nvim-data/mason/bin/xmlformat.cmd",
                }, "xmlformat"),
                args = { "--indent", 4, vim.api.nvim_buf_get_name(bufnr) },
            }
        else
            return {
                command = require("conform.util").find_executable({
                    home .. "/.local/share/nvim/mason/bin",
                }, "xmlformat"),
                args = { "--indent", 4, vim.api.nvim_buf_get_name(bufnr) },
            }
        end
    end
end



if not vim.g.lite then
    vim.schedule(function()
        if io.open(vim.loop.cwd() .. "/.nvim/init.lua", "r") ~= nil then
            vim.api.nvim_command("source " .. vim.loop.cwd() .. "/.nvim/init.lua")
        end

        vim.schedule(require("persistence").load)
        vim.cmd.colorscheme("catppuccin-mocha")
    end)

    require("maven-tools").setup()
end
