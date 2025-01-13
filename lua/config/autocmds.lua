-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

vim.api.nvim_create_autocmd("FileType", {
    callback = function()
        vim.b.autoformat = false
    end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
    callback = function()
        pcall(function()
            if vim.g.vscode then
                require("vscode").action("workbench.action.files.save")
            else
                vim.api.nvim_command("w")
            end
        end)
    end,
})

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
        if vim.g.vscode then
            -- require("vscode").action("workbench.action.files.save")
        else
            vim.api.nvim_command("wa")
        end
    end,
})

if not vim.g.lite then
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            local homeDir = os.getenv("HOME") or os.getenv("USERPROFILE")

            if not homeDir then
                return
            end

            local configDir = homeDir .. "/.config"

            if not os.rename(configDir, configDir) then
                os.execute("mkdir " .. configDir)
            end

            configDir = configDir .. "/nvim"

            if not os.rename(configDir, configDir) then
                os.execute("mkdir " .. configDir)
            end

            configDir = configDir .. "/.nvim"

            if not os.rename(configDir, configDir) then
                os.execute("mkdir " .. configDir)
            end

            local configFile = configDir .. "/.lastSession"

            local file = io.open(configFile, "w")
            if file then
                file:write(vim.loop.cwd())
                file:close()
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Auto select virtualenv Nvim open",
        pattern = "*",
        callback = function()
            local venv = vim.fn.findfile("pyproject.toml", vim.fn.getcwd() .. ";")
            if venv ~= "" then
                require("venv-selector").retrieve_from_cache()
            end
        end,
        once = true,
    })

    -- vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    --     callback = function()
    --         require("lint").try_lint()
    --     end,
    -- })

    vim.cmd[[
        augroup jdtls_lsp
            autocmd!
            autocmd FileType java lua require("config/jdtls").setup_jdtls()
        augroup end
    ]]
end
