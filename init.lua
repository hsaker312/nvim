vim.g.vscode = false
-- bootstrap lazy.nvim, LazyVim and your plugins
local handle = io.popen("git pull")

if handle then
    handle:close()
end

require("config.lazy")
