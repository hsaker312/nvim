-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
-- vim.keymap.set({ "n", "v" }, "q", "<nop>")
-- vim.keymap.set({ "n", "v" }, "Q", "<nop>")
vim.keymap.set({ "n", "v" }, "L", "<nop>")

require("config.keymaps.utils")
require("config.keymaps.findReplace")
require("config.keymaps.edit")
require("config.after")

if vim.g.vscode then
    require("config.keymaps.vscode")
else
    require("config.keymaps.plugins")
end
