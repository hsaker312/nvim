-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
vim.keymap.set({ "n", "v" }, "q", "<nop>")
vim.keymap.set({ "n", "v" }, "Q", "<nop>")
-- --
require("config.keymaps.utils")
require("config.keymaps.findReplace")
require("config.keymaps.plugins")
require("config.keymaps.edit")
require("config.after")

