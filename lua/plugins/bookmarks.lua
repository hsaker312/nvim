return {
    "tomasky/bookmarks.nvim",
    config = function()
        local save_path = ""

        if package.cpath:match("%p[\\|/]?%p(%a+)") == "so" then
            save_path = vim.loop.cwd() .. "/.nvim/.bookmarks.linux.json"
        else
            save_path = vim.loop.cwd() .. "/.nvim/.bookmarks.win.json"
        end

        require("bookmarks").setup({
            save_file = save_path,
        })
        require("telescope").load_extension("bookmarks")
    end,
}
