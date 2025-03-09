-- bootstrap lazy.nvim, LazyVim and your plugins

local preset = vim.env.NVIM_PRESET

vim.g.windows = package.cpath:match("%p[\\|/]?%p(%a+)") == "dll"

if preset == "lite" then
    vim.g.lite = true
else
    local config_path = vim.fn.stdpath("config")

    if type(config_path) == "table" then
        config_path = config_path[1]
    end
    if type(config_path) == "string" then
        local handle = io.popen("cd " .. config_path .. "&& git pull")

        if handle then
            handle:close()
        end
    end
end

require("config.lazy")
