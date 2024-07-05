-- vim.keymap.set({ "n", "i" }, "<A-C-l>", require("conform").format)

vim.keymap.set("n", "<A-C-;>", function()
    vim.api.nvim_feedkeys("V", "", true)
    vim.defer_fn(function()
        require("lazyvim.util").format({ force = true })
        vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "", true)
        end, 25)
    end, 25)
end, { noremap = true, silent = true, desc = "Format Line" })

vim.keymap.set("i", "<A-C-;>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>V", true, true, true), "", true)

    vim.defer_fn(function()
        require("lazyvim.util").format({ force = true })

        vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>a", true, true, true), "", true)
        end, 25)
    end, 25)
end, { noremap = true, silent = true, desc = "Format Line" })

vim.keymap.set("v", "<A-C-;>", function()
    require("lazyvim.util").format({ force = true })
end, { noremap = true, silent = true, desc = "Format Selection" })

vim.keymap.set(
    "n",
    "<leader><leader>",
    vim.lsp.buf.code_action,
    { noremap = true, silent = true, desc = "Lsp Code Action" }
)

vim.keymap.set("n", "<A-/>", function()
    vim.api.nvim_feedkeys("gcc", "", true)
end, { noremap = true, silent = true, desc = "Comment Line" })
vim.keymap.set("i", "<A-/>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>gccji", true, true, true), "", true)
end, { noremap = true, silent = true, desc = "Comment Line" })
vim.keymap.set("v", "<A-/>", function()
    vim.api.nvim_feedkeys("gc", "", true)
end, { noremap = true, silent = true, desc = "Comment Selected" })

vim.keymap.set("n", "<leader>(", function()
    vim.api.nvim_feedkeys("ds(", "", true)
end, { noremap = true, silent = true, desc = "Remove ()" })
vim.keymap.set("n", "<leader>[", function()
    vim.api.nvim_feedkeys("ds[", "", true)
end, { noremap = true, silent = true, desc = "Remove []" })
vim.keymap.set("n", "<leader>{", function()
    vim.api.nvim_feedkeys("ds{", "", true)
end, { noremap = true, silent = true, desc = "Remove {}" })
vim.keymap.set("n", "<leader><", function()
    vim.api.nvim_feedkeys("ds<", "", true)
end, { noremap = true, silent = true, desc = "Remove <>" })
vim.keymap.set("n", '<leader>"', function()
    vim.api.nvim_feedkeys('ds"', "", true)
end, { noremap = true, silent = true, desc = 'Remove ""' })
vim.keymap.set("n", "<leader>'", function()
    vim.api.nvim_feedkeys("ds'", "", true)
end, { noremap = true, silent = true, desc = "Remove ''" })

vim.keymap.set(
    "n",
    "<leader>db",
    "<cmd> PBToggleBreakpoint <CR>",
    { noremap = true, silent = true, desc = "Debug Break Point" }
)
vim.keymap.set("n", "<leader>di", "<cmd> DapStepInto <CR>", { noremap = true, silent = true, desc = "Debug Step Into" })
vim.keymap.set("n", "<leader>do", "<cmd> DapStepOut <CR>", { noremap = true, silent = true, desc = "Debug Step Out" })
vim.keymap.set("n", "<leader>ds", "<cmd> DapStepOver <CR>", { noremap = true, silent = true, desc = "Debug Step Over" })
vim.keymap.set(
    "n",
    "<leader>dt",
    "<cmd> DapTerminate <CR>",
    { noremap = true, silent = true, desc = "Debug Terminate" }
)
vim.keymap.set("n", "<leader>dc", "<cmd> DapContinue <CR>", { noremap = true, silent = true, desc = "Debug Continue" })
vim.keymap.set(
    "n",
    "<leader>dr",
    "<cmd> DapRestartFrame <CR>",
    { noremap = true, silent = true, desc = "Debug Restart" }
)
vim.keymap.set("n", "<leader>du", function()
    require("dapui").toggle()
end, { noremap = true, silent = true, desc = "Toggle Debug UI" })

vim.keymap.set(
    "n",
    "<leader>ff",
    function ()
        require("telescope.builtin").find_files({ hidden = true })
    end,
    { noremap = true, silent = true, desc = "Find Files" }
)
vim.keymap.set(
    "n",
    "<leader>fm",
    "<cmd> Telescope bookmarks list <CR>",
    { noremap = true, silent = true, desc = "Find Bookmarks" }
)

vim.keymap.set(
    "n",
    "<leader>bm",
    require("bookmarks").bookmark_toggle,
    { noremap = true, silent = true, desc = "Toggle Bookmarks" }
)

vim.keymap.set(
    "n",
    "<leader><C-right>",
    "<cmd> BufferLineMoveNext <CR>",
    { noremap = true, silent = true, desc = "Move Buffer Right" }
)
vim.keymap.set(
    "n",
    "<leader><C-left>",
    "<cmd> BufferLineMovePrev <CR>",
    { noremap = true, silent = true, desc = "Move Buffer Left" }
)
vim.keymap.set(
    {"n", "v"},
    "<leader><right>",
    "<cmd> BufferLineCycleNext <CR>",
    { noremap = true, silent = true, desc = "Go To Next Buffer" }
)
vim.keymap.set(
    {"n", "v"},
    "<leader><left>",
    "<cmd> BufferLineCyclePrev <CR>",
    { noremap = true, silent = true, desc = "Go To Previous Buffer" }
)

vim.keymap.set(
    "n",
    "<leader><C-l>",
    "<cmd> BufferLineMoveNext <CR>",
    { noremap = true, silent = true, desc = "Move Buffer Right" }
)
vim.keymap.set(
    "n",
    "<leader><C-h>",
    "<cmd> BufferLineMovePrev <CR>",
    { noremap = true, silent = true, desc = "Move Buffer Left" }
)
vim.keymap.set(
    {"n", "v"},
    "<leader>l",
    "<cmd> BufferLineCycleNext <CR>",
    { noremap = true, silent = true, desc = "Go To Next Buffer" }
)
vim.keymap.set(
    {"n", "v"},
    "<leader>h",
    "<cmd> BufferLineCyclePrev <CR>",
    { noremap = true, silent = true, desc = "Go To Previous Buffer" }
)

vim.keymap.set(
    "n",
    "n",
    [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]],
    { noremap = true, silent = true, desc = "Go To Next Find" }
)
vim.keymap.set(
    "n",
    "N",
    [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]],
    { noremap = true, silent = true, desc = "Go To Previous Find" }
)

vim.keymap.set(
    "n",
    "*",
    [[*<Cmd>lua require('hlslens').start()<CR>]],
    { noremap = true, silent = true, desc = "Go To Next Find" }
)
vim.keymap.set(
    "n",
    "#",
    [[#<Cmd>lua require('hlslens').start()<CR>]],
    { noremap = true, silent = true, desc = "Go To Previous Find" }
)
vim.keymap.set(
    "n",
    "g*",
    [[g*<Cmd>lua require('hlslens').start()<CR>]],
    { noremap = true, silent = true, desc = "Go To Next Find" }
)
vim.keymap.set(
    "n",
    "g#",
    [[g#<Cmd>lua require('hlslens').start()<CR>]],
    { noremap = true, silent = true, desc = "Go To Previous Find" }
)

vim.keymap.set(
    "n",
    "gs",
    "<Cmd>ISwap<CR>",
    { noremap = true, silent = true, desc = "Swap Arguments" }
)

