vim.g.vscode = true
local handle = io.popen("git pull")

if handle then
    handle:close()
end

require("config.lazy")
