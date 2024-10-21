local function get_selected_text()
    local line_start = vim.fn.line("v")
    local line_end = vim.fn.line(".")
    local col_start = vim.fn.col("v")
    local col_end = vim.fn.col(".")

    local ls = line_start
    local le = line_end
    local cs = col_start
    local ce = col_end

    if line_start > line_end then
        ls = line_end
        le = line_start
        cs = col_end
        ce = col_start
    elseif line_start == line_end and col_end < col_start then
        cs = col_end
        ce = col_start
    elseif line_start == line_end and col_start == col_end then
        cs = 1
        ce = #vim.fn.getline(line_start)
    end

    local selected_text = ""
    for line = ls, le do
        local line_text = vim.fn.getline(line)
        local start_col = (line == ls) and cs or 1
        local end_col = (line == le) and ce or #line_text

        selected_text = selected_text .. line_text:sub(start_col, end_col)
        if line ~= le then
            selected_text = selected_text .. "\n"
        end
    end

    return selected_text, le, ce
end

--"C:\Users\saker.helmy\aws\key.private.key|5 col 7|"

---@return integer
local function get_editor_window()
    local windows = vim.api.nvim_tabpage_list_wins(0) -- Get all windows in the current tab page

    for _, win in ipairs(windows) do
        local buf = vim.api.nvim_win_get_buf(win) -- Get the buffer associated with the window
        local buf_name = vim.api.nvim_buf_get_name(buf) -- Get the buffer's name

        if buf_name ~= nil and buf_name ~= "" then
            if buf_name:match("[%[|%]]") == nil then
                return win
            end
        end
    end

    return vim.api.nvim_get_current_win()
end

local goto_to_link = function(mouse)
    if mouse then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true), "", true)
    end

    vim.defer_fn(function()
        local inputString = vim.fn.getline(vim.fn.line("."))

        if vim.api.nvim_get_mode().mode == "v" then
            inputString, _, _ = get_selected_text()
        else
            inputString = vim.fn.getline(vim.fn.line("."))
        end

        local path, line, col = inputString:match(
            '[%s]+([^:<>"|?*%[%]]+:?[^:<>"|?*%[%]]+%.[^:<>"|?*%[%]]+)[:, |]?(%d*)%s*c?o?l?%s*([0-9]*|?).*'
        )

        if path == nil then
            path, line, col = inputString:match(
                '^([^:<>"|?*%[%]]+:?[^:<>"|?*%[%]]+%.[^:<>"|?*%[%]]+)[:, |]?(%d*)%s*c?o?l?%s*([0-9]*|?).*'
            )
        end

        if line then
            line = line:match("[^%d]*(%d+)[^%d]*")
        end

        if col then
            col = col:match("[^%d]*(%d+)[^%d]*")
        end

        if path ~= nil then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<c-k>", true, true, true), "", true)

            vim.defer_fn(function()
                local buffers = vim.api.nvim_list_bufs()
                local buffer = nil

                for _, buf in ipairs(buffers) do
                    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
                        if vim.api.nvim_buf_get_name(buf):match(".+" .. path .. "$") then
                            buffer = buf
                            break
                        end
                    end
                end

                if buffer == nil then
                    vim.api.nvim_command("edit " .. path)
                else
                    vim.api.nvim_win_set_buf(get_editor_window(), buffer)
                end

                vim.schedule(function()
                    if line ~= nil and col ~= nil then
                        vim.api.nvim_command("call cursor(" .. line .. "," .. col .. ")")
                    elseif line ~= nil then
                        vim.api.nvim_command(line)
                    end
                end)
            end, 100)
        end
    end, 100)
end

vim.keymap.set({ "i", "v", "n" }, "<C-Del>", "<esc>")

vim.keymap.set("n", "<MiddleMouse>", function()
    goto_to_link(true)
end, { noremap = true, silent = true, desc = "Open Link" })

vim.keymap.set("n", "<leader><cr>", function()
    goto_to_link(false)
end, { noremap = true, silent = true, desc = "Open Link" })

vim.keymap.set("v", "<leader><cr>", function()
    goto_to_link(false)
end, { noremap = true, silent = true, desc = "Open Link" })

vim.keymap.set("n", "]>", "va<<esc>", { noremap = true, silent = true, desc = "Next <" })
vim.keymap.set("n", "[<", "va<o<esc>", { noremap = true, silent = true, desc = "Perv <" })

vim.keymap.set("n", "]'", "va'<esc>", { noremap = true, silent = true, desc = "Next '" })
vim.keymap.set("n", "['", "va'o<esc>", { noremap = true, silent = true, desc = "Perv '" })

vim.keymap.set("n", "]a", function()
    local line_num = vim.fn.line(".")
    local col_num = vim.fn.col(".")
    local line_len = #vim.fn.getline(line_num)

    if
        col_num >= line_len
        or (((col_num + 1) >= line_len) and vim.fn.getline(line_num):sub(col_num + 1, col_num + 1) == ",")
    then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<down>_vaao<esc>", true, true, true), "", true)
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<right><right>vaao<esc>", true, true, true), "", true)
    end

    vim.defer_fn(function()
        line_num = vim.fn.line(".")
        col_num = vim.fn.col(".")

        if vim.fn.getline(line_num):sub(col_num, col_num) == "," then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<left>", true, true, true), "", true)
        end
    end, 10)
end, { noremap = true, silent = true, desc = "Next Argument" })

vim.keymap.set("n", "[a", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<left>vaa<esc>", true, true, true), "", true)

    vim.defer_fn(function()
        local line_num = vim.fn.line(".")
        local col_num = vim.fn.col(".")

        if vim.fn.getline(line_num):sub(col_num, col_num) == "," then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<left>", true, true, true), "", true)
        end
    end, 10)
end, { noremap = true, silent = true, desc = "perv Argument" })

vim.keymap.set("n", ']"', 'va"<esc>', { noremap = true, silent = true, desc = 'Next "' })
vim.keymap.set("n", '["', 'va"o<esc>', { noremap = true, silent = true, desc = 'Perv "' })

vim.keymap.set("n", "<A-LeftMouse>", "<C-o>", { noremap = true, silent = true, desc = "Back" })
vim.keymap.set("n", "<A-Left>", "<C-o>", { noremap = true, silent = true, desc = "Back" })
vim.keymap.set("n", "<A-h>", "<C-o>", { noremap = true, silent = true, desc = "Back" })

vim.keymap.set("n", "<A-RightMouse>", "<C-i>", { noremap = true, silent = true, desc = "Forward" })
vim.keymap.set("n", "<A-Right>", "<C-i>", { noremap = true, silent = true, desc = "Forward" })
vim.keymap.set("n", "<A-l>", "<C-i>", { noremap = true, silent = true, desc = "Forward" })

vim.keymap.set("n", "<A-up>", "v:m '<-2<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Up" })
vim.keymap.set(
    "i",
    "<A-up>",
    "<esc>v:m '<-2<CR>gv=gv<esc>a",
    { noremap = true, silent = true, desc = "Move Line Down" }
)
vim.keymap.set("v", "<A-up>", ":m '<-2<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Up" })

vim.keymap.set("n", "<A-k>", "v:m '<-2<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Up" })
vim.keymap.set("i", "<A-k>", "<esc>v:m '<-2<CR>gv=gv<esc>a", { noremap = true, silent = true, desc = "Move Line Down" })
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Up" })

vim.keymap.set("n", "<A-down>", "v:m '>+1<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Down" })
vim.keymap.set(
    "i",
    "<A-down>",
    "<esc>v:m '>+1<CR>gv=gv<esc>a",
    { noremap = true, silent = true, desc = "Move Line Down" }
)
vim.keymap.set("v", "<A-down>", ":m '>+1<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Down" })

vim.keymap.set("n", "<A-j>", "v:m '>+1<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Down" })
vim.keymap.set("i", "<esc>v:m '>+1<CR>gv=gv<esc>a", "<A-j>", { noremap = true, silent = true, desc = "Move Line Down" })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { noremap = true, silent = true, desc = "Move Line Down" })

vim.keymap.set({ "n", "i", "v" }, "<C-z>", "<cmd>undo<CR>", { noremap = true, silent = true, desc = "Undo" })
vim.keymap.set({ "n", "i", "v" }, "<C-y>", "<cmd>redo<CR>", { noremap = true, silent = true, desc = "Redo" })

vim.keymap.set("n", "<S-right>", "v<right>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("i", "<S-right>", "<right><esc>v<right>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<S-right>", "<right>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<right>", "<esc>", { noremap = true, silent = true, desc = "Select Text" })

vim.keymap.set("n", "<S-up>", "v<up>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("i", "<S-up>", "<C-c>v<up>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<S-up>", "<up>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<up>", "<esc>", { noremap = true, silent = true, desc = "Select Text" })

vim.keymap.set("n", "<S-down>", "v<down>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("i", "<S-down>", "<right><esc>v<down>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<S-down>", "<down>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<down>", "<esc>", { noremap = true, silent = true, desc = "Select Text" })

vim.keymap.set("n", "<S-left>", "v<left>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("i", "<S-left>", "<C-c>v<left>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<S-left>", "<left>", { noremap = true, silent = true, desc = "Select Text" })
vim.keymap.set("v", "<left>", "<esc>", { noremap = true, silent = true, desc = "Select Text" })

vim.keymap.set("n", "<Home>", "_", { noremap = true, silent = true, desc = "Go To Line Start" })
vim.keymap.set("i", "<Home>", "<esc>_i", { noremap = true, silent = true, desc = "Go To Line Start" })
vim.keymap.set("v", "<Home>", "_", { noremap = true, silent = true, desc = "Go To Line Start" })

local select_all_old_cursor = nil

vim.keymap.set("n", "<C-a>", function()
    select_all_old_cursor = vim.api.nvim_win_get_cursor(0)

    vim.api.nvim_command("normal! 0ggvG$")
end, { noremap = true, silent = true, desc = "Select All" })

vim.keymap.set("i", "<C-a>", "<esc>0ggvG", { noremap = true, silent = true, desc = "Select All" })

vim.keymap.set("v", "<C-a>", function()
    if select_all_old_cursor then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "", true)
        vim.api.nvim_command(
            "call cursor(" .. tostring(select_all_old_cursor[1] .. "," .. tostring(select_all_old_cursor[2] .. ")"))
        )

        select_all_old_cursor = nil
    end
end, { noremap = true, silent = true, desc = "Multi-Cursor Mode" })

vim.keymap.set("n", "<leader>qa", "<cmd>qa<cr>", { noremap = true, silent = true, desc = "Quit All" })
vim.keymap.set("n", "<leader>qq", "<cmd>q<cr>", { noremap = true, silent = true, desc = "Quit" })

vim.keymap.set({ "n", "v" }, "<C-left>", "<C-w>h", { noremap = true, silent = true, desc = "Focus Left" })
vim.keymap.set({ "n", "v" }, "<C-right>", "<C-w>l", { noremap = true, silent = true, desc = "Focus Right" })
vim.keymap.set({ "n", "v" }, "<C-up>", "<C-w>k", { noremap = true, silent = true, desc = "Focus Up" })
vim.keymap.set({ "n", "v" }, "<C-down>", "<C-w>j", { noremap = true, silent = true, desc = "Focus Down" })

-- vim.keymap.set("i", "<C-left>", "<esc><C-w>h", { noremap = true, silent = true, desc = "Focus Left" })
-- vim.keymap.set("i", "<C-right>", "<esc><C-w>l", { noremap = true, silent = true, desc = "Focus Right" })
-- vim.keymap.set("i", "<C-up>", "<esc><C-w>k", { noremap = true, silent = true, desc = "Focus Up" })
-- vim.keymap.set("i", "<C-down>", "<esc><C-w>j", { noremap = true, silent = true, desc = "Focus Down" })

vim.keymap.set({ "n", "v" }, "<C-h>", "<C-w>h", { noremap = true, silent = true, desc = "Focus Left" })
vim.keymap.set({ "n", "v" }, "<C-l>", "<C-w>l", { noremap = true, silent = true, desc = "Focus Right" })
vim.keymap.set({ "n", "v" }, "<C-k>", "<C-w>k", { noremap = true, silent = true, desc = "Focus Up" })
vim.keymap.set({ "n", "v" }, "<C-j>", "<C-w>j", { noremap = true, silent = true, desc = "Focus Down" })

vim.keymap.set("i", "<C-h>", "<esc><C-w>h", { noremap = true, silent = true, desc = "Focus Left" })
vim.keymap.set("i", "<C-l>", "<esc><C-w>l", { noremap = true, silent = true, desc = "Focus Right" })
vim.keymap.set("i", "<C-k>", "<esc><C-w>k", { noremap = true, silent = true, desc = "Focus Up" })
vim.keymap.set("i", "<C-j>", "<esc><C-w>j", { noremap = true, silent = true, desc = "Focus Down" })

vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-left>",
    "<cmd>vertical resize -2<cr>",
    { noremap = true, silent = true, desc = "Decrease Window Width" }
)
vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-right>",
    "<cmd>vertical resize +2<cr>",
    { noremap = true, silent = true, desc = "Increase Window Width" }
)
vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-up>",
    "<cmd>resize +2<cr>",
    { noremap = true, silent = true, desc = "Increase Window Height" }
)
vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-down>",
    "<cmd>resize -2<cr>",
    { noremap = true, silent = true, desc = "Decrease Window Height" }
)

vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-h>",
    "<cmd>vertical resize -2<cr>",
    { noremap = true, silent = true, desc = "Decrease Window Width" }
)
vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-l>",
    "<cmd>vertical resize +2<cr>",
    { noremap = true, silent = true, desc = "Increase Window Width" }
)
vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-k>",
    "<cmd>resize +2<cr>",
    { noremap = true, silent = true, desc = "Increase Window Height" }
)
vim.keymap.set(
    { "n", "v", "i" },
    "<A-C-j>",
    "<cmd>resize -2<cr>",
    { noremap = true, silent = true, desc = "Decrease Window Height" }
)

vim.keymap.set({ "n", "v" }, "<leader><up>", "zt", { noremap = true, silent = true, desc = "Sroll Page Up" })
vim.keymap.set({ "n", "v" }, "<leader>k", "zt", { noremap = true, silent = true, desc = "Sroll Page Up" })
vim.keymap.set({ "n", "v" }, "<leader><down>", "zb", { noremap = true, silent = true, desc = "Sroll Page Down" })
vim.keymap.set({ "n", "v" }, "<leader>j", "zb", { noremap = true, silent = true, desc = "Sroll Page Down" })

vim.keymap.set(
    "n",
    "<leader><leader>",
    vim.lsp.buf.code_action,
    { noremap = true, silent = true, desc = "Lsp Code Action" }
)
vim.keymap.set("n", "<leader>cd", vim.lsp.buf.definition, { noremap = true, silent = true, desc = "Go To Definition" })
vim.keymap.set(
    "n",
    "<leader>cD",
    vim.lsp.buf.declaration,
    { noremap = true, silent = true, desc = "Go To Declaration" }
)
vim.keymap.set(
    "n",
    "<leader>ci",
    vim.lsp.buf.implementation,
    { noremap = true, silent = true, desc = "GO To Implementation" }
)
vim.keymap.set(
    "n",
    "<leader>ch",
    vim.lsp.buf.signature_help,
    { noremap = true, silent = true, desc = "Show Signature Docs" }
)
vim.keymap.set(
    "n",
    "<leader>ct",
    vim.lsp.buf.type_definition,
    { noremap = true, silent = true, desc = "Go To Type Definition" }
)
vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, { noremap = true, silent = true, desc = "Rename Reference" })
vim.keymap.set(
    "n",
    "<leader>sl",
    "<cmd> Telescope lsp_references <CR>",
    { noremap = true, silent = true, desc = "Find Symbol References (Telescope)" }
)
vim.keymap.set(
    "n",
    "<leader>sL",
    vim.lsp.buf.references,
    { noremap = true, silent = true, desc = "Find Symbol References" }
)
vim.keymap.set(
    "n",
    "<leader>cp",
    require("diagnostics-details").show,
    { noremap = true, silent = true, desc = "Show Detailed Diagnostics" }
)

vim.keymap.set(
    "n",
    "<leader>cP",
    vim.diagnostic.open_float,
    { noremap = true, silent = true, desc = "Show Diagnostics" }
)
