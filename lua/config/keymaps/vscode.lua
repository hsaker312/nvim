local vscode = require("vscode")


vim.keymap.set({"n", "v"}, "<leader>bd", function()
    vscode.action("workbench.action.closeActiveEditor")
end)

vim.keymap.set({"n", "v"}, "<leader><right>", function()
    vscode.action("workbench.action.nextEditor")
end)

vim.keymap.set({"n", "v"}, "<leader><left>", function()
    vscode.action("workbench.action.previousEditor")
end)

vim.keymap.set({"n", "v"}, "]w", function()
    vscode.action("editor.action.marker.nextInFiles")
end)

vim.keymap.set({"n", "v"}, "[w", function()
    vscode.action("editor.action.marker.prevInFiles")
end)

vim.keymap.set({"n", "v"}, "]e", function()
    vscode.action("editor.action.marker.nextInFiles")
end)

vim.keymap.set({"n", "v"}, "[e", function()
    vscode.action("editor.action.marker.prevInFiles")
end)

vim.keymap.set({"n", "v"}, "]d", function()
    vscode.action("editor.action.marker.nextInFiles")
end)

vim.keymap.set({"n", "v"}, "[d", function()
    vscode.action("editor.action.marker.prevInFiles")
end)

vim.keymap.set({"n", "v"}, "<leader>cp", function()
    vscode.action("editor.action.marker.nextInFiles")
end)

vim.keymap.set({"n", "v"}, "<leader>ff", function()
    vscode.action("workbench.action.quickOpen")
end)

vim.keymap.set("n", "<leader>sl", vim.lsp.buf.references, { noremap = true, silent = true, desc = "Find Symbol References" })

vim.keymap.set({"n", "v"}, "<leader><leader>", function()
    vscode.action('editor.action.quickFix')
end, { noremap = true, silent = true, desc = "Quickfix" })

vim.keymap.set({"n", "v"}, "<leader>db", function()
    vscode.action('editor.debug.action.toggleBreakpoint')
end, { noremap = true, silent = true, desc = "Toggle Breakpoint" })

vim.keymap.set("n", "<leader>cf", function()
    vscode.action("editor.action.formatDocument")
end, { noremap = true, silent = true, desc = "Format Document" })

vim.keymap.set("v", "<leader>cf", function()
    vscode.action("editor.action.formatSelection")
end, { noremap = true, silent = true, desc = "Format Document" })

vim.keymap.set({ "n", "i", "v" }, "<C-s>", function()
    vscode.action("workbench.action.files.save")
    vim.api.nvim_command("stopinsert")
end)

