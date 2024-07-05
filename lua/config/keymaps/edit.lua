local get_le_ce = function()
    local line_start = vim.fn.line("v")
    local line_end = vim.fn.line(".")
    local col_start = vim.fn.col("v")
    local col_end = vim.fn.col(".")

    local le = line_end
    local ce = col_end

    if line_start > line_end then
        le = line_start
        ce = col_start
    elseif line_start == line_end and col_end < col_start then
        ce = col_start
    elseif line_start == line_end and col_start == col_end then
        ce = #vim.fn.getline(line_start)
    end

    return le, ce
end

local get_ls_cs_le_ce = function()
    local line_start = vim.fn.line("v")
    local line_end = vim.fn.line(".")
    local col_start = vim.fn.col("v")
    local col_end = vim.fn.col(".")

    local ls = line_start
    local cs = col_start
    local le = line_end
    local ce = col_end

    if line_start > line_end then
        ls = line_end
        cs = col_end
        le = line_start
        ce = col_start
    elseif line_start == line_end and col_end < col_start then
        cs = col_end
        ce = col_start
    end

    return ls, cs, le, ce
end

local delete_selected = function()
    local reg1 = vim.fn.getreg('"')
    local reg2 = vim.fn.getreg("+")

    local le, ce = get_le_ce()
    local linelen = #vim.fn.getline(le)

    vim.api.nvim_command("normal! x")

    vim.schedule(function()
        vim.fn.setreg('"', reg1)
        vim.fn.setreg("+", reg2)

        if vim.api.nvim_get_mode().mode == "n" then
            if ce >= linelen then
                vim.api.nvim_command("startinsert!")
            else
                vim.api.nvim_command("startinsert")
            end
        end
    end)
end
--
-- local surround_selected = function(open, close)
--     local isVisualMode = vim.fn.mode():find("[Vv]")
--     if not isVisualMode then
--         return
--     end
--
--     local line_start = vim.fn.line("v")
--     local line_end = vim.fn.line(".")
--     local col_start = vim.fn.col("v")
--     local col_end = vim.fn.col(".")
--
--     if line_start > line_end then
--         local temp = line_start
--         line_start = line_end
--         line_end = temp
--
--         temp = col_start
--         col_start = col_end
--         col_end = temp
--     elseif line_start == line_end and col_start > col_end then
--         local temp = col_start
--         col_start = col_end
--         col_end = temp
--     end
--
--     vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_start, col_start - 1 })
--
--     if open == "<" then
--         vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>i" .. open, true, true, true), "", true)
--     else
--         vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>i" .. open .. "<Del>", true, true, true), "", true)
--     end
--
--     vim.defer_fn(function()
--         vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_end, col_end })
--
--         vim.defer_fn(function()
--             local lastLine = vim.fn.getline(line_end)
--             local lastLineLen = #lastLine
--             local chars = ""
--
--             vim.defer_fn(function()
--                 vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<right>" .. close, true, true, true), "", true)
--
--                 vim.defer_fn(function()
--                     local i = 2
--
--                     while lastLineLen >= col_end + i do
--                         local char = lastLine:sub(col_end + i, col_end + i)
--
--                         if close == char and char ~= ">" then
--                             chars = chars .. close
--                         else
--                             break
--                         end
--
--                         i = i + 1
--                     end
--
--                     vim.defer_fn(function()
--                         vim.api.nvim_feedkeys(chars, "", true)
--
--                         vim.defer_fn(function()
--                             if close == open then
--                                 vim.api.nvim_feedkeys(
--                                     vim.api.nvim_replace_termcodes("<Del><esc>", true, true, true),
--                                     "",
--                                     true
--                                 )
--                             else
--                                 vim.api.nvim_feedkeys(
--                                     vim.api.nvim_replace_termcodes("<esc>", true, true, true),
--                                     "",
--                                     true
--                                 )
--                             end
--
--                             vim.defer_fn(function()
--                                 vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_start, col_start })
--                                 vim.api.nvim_command("normal! v")
--
--                                 if close == open then
--                                     if line_start ~= line_end then
--                                         vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_end, col_end })
--                                     else
--                                         vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_end, col_end + 1 })
--                                     end
--                                 else
--                                     if line_start ~= line_end then
--                                         vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_end, col_end - 1 })
--                                     else
--                                         vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { line_end, col_end })
--                                     end
--                                 end
--                             end, 10)
--                         end, 10)
--                     end, 10)
--                 end, 10)
--             end, 10)
--         end, 10)
--     end, 10)
-- end

local surround_selected = function(open, close)
    local isVisualMode = vim.fn.mode():find("[Vv]")
    if not isVisualMode then
        return
    end

    local ls, cs, le, ce = get_ls_cs_le_ce()

    ---@diagnostic disable-next-line: cast-local-type
    ls = tostring(ls)
    ---@diagnostic disable-next-line: cast-local-type
    le = tostring(le)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>" .. open, true, true, true), "", true)

    vim.defer_fn(function()
        vim.api.nvim_command("call cursor(" .. ls .. "," .. tostring(cs) .. ")")
        vim.api.nvim_command("normal! i" .. open)

        vim.api.nvim_command("call cursor(" .. le .. "," .. tostring(ce + 1) .. ")")
        vim.api.nvim_command("normal! a" .. close)
        vim.api.nvim_command("call cursor(" .. ls .. "," .. tostring(cs + 1) .. ")")
        vim.api.nvim_command("normal! v")

        if ls == le then
            vim.api.nvim_command("call cursor(" .. le .. "," .. tostring(ce + 1) .. ")")
        else
            vim.api.nvim_command("call cursor(" .. le .. "," .. tostring(ce) .. ")")
        end
    end, 25)
end

local paste = function(reg)
    if reg == nil then
        reg = "+"
    end

    local _, cs, le, ce = get_ls_cs_le_ce()
    local lines = vim.fn.getreg(reg)
    local lines_count = 0
    local last_line_len = 0

    for line in lines:gmatch("[^\n]*\n") do
        lines_count = lines_count + 1
        last_line_len = #line
    end

    lines_count = lines_count - 1

    if lines_count < 1 then
        if cs == 1 then
            vim.api.nvim_command("normal! P")
            vim.api.nvim_command("normal! l")
        elseif ce > #vim.fn.getline(le) then
            vim.api.nvim_command("normal! p")
            vim.api.nvim_command("startinsert!")
        else
            vim.api.nvim_command("normal! P")
            vim.api.nvim_command("normal! l")
        end
    else
        if ce > #vim.fn.getline(le) then
            vim.api.nvim_command("normal! p")
        else
            vim.api.nvim_command("normal! P")
        end

        vim.api.nvim_command("call cursor(" .. tostring(le + lines_count + 1) .. "," .. tostring(last_line_len + 1) .. ")")
    end
end

vim.keymap.set("v", "<Del>", delete_selected, { noremap = true, silent = true, desc = "Delete Selected" })

vim.keymap.set("n", "<C-x>", "V<Del>", { noremap = true, silent = true, desc = "Cut Line" })
vim.keymap.set("i", "<C-x>", "<esc>V<Del>", { noremap = true, silent = true, desc = "Cut Line" })
vim.keymap.set("v", "<C-x>", "<Del>i", { noremap = true, silent = true, desc = "Cut Selected" })

vim.keymap.set({ "n", "i" }, "<C-c>", "<esc>", { noremap = true, silent = true, desc = "Copy Line" })
vim.keymap.set("v", "<C-c>", '"+y<esc>gv', { noremap = true, silent = true, desc = "Copy Selected" })

vim.keymap.set("n", "<C-v>", function()
    local col_num = vim.fn.col(".")

    vim.api.nvim_command("startinsert")

    if col_num > 1 then
        vim.api.nvim_command("normal! l")
    end

    paste()
end, { noremap = true, silent = true, desc = "Paste" })

vim.keymap.set("i", "<C-v>", paste, { noremap = true, silent = true, desc = "Paste" })
vim.keymap.set("v", "<C-v>", function()
    delete_selected()
    vim.schedule(paste)
end, { noremap = true, silent = true, desc = "Paste Over Selected" })

vim.keymap.set(
    "n",
    "<C-d>",
    'a<esc>V"ay<esc><end>"apgi<esc><down>',
    { noremap = true, silent = true, desc = "Duplicate Line" }
)
vim.keymap.set(
    "i",
    "<C-d>",
    '<esc>V"ay<esc><end>"apgi<down>',
    { noremap = true, silent = true, desc = "Duplicate Line" }
)
vim.keymap.set(
    "v",
    "<C-d>",
    '"aygvo<esc><end>a<cr><esc>"apgvo',
    { noremap = true, silent = true, desc = "Duplicate Lines" }
)

vim.keymap.set("n", "<tab>", ">0llll", { noremap = true, silent = true, desc = "Shift Line Right" })

vim.keymap.set("v", "<tab>", function()
    local ls, cs, le, ce = get_ls_cs_le_ce()
    ---@diagnostic disable-next-line: undefined-field
    local tab_width = vim.opt.tabstop:get()

    vim.api.nvim_command("normal! >")
    vim.api.nvim_command("call cursor(" .. tostring(ls) .. "," .. tostring(cs + tab_width) .. ")")
    vim.api.nvim_command("normal! v")
    vim.api.nvim_command("call cursor(" .. tostring(le) .. "," .. tostring(ce + tab_width) .. ")")
end, { noremap = true, silent = true, desc = "Shift Line Right" })

---NOTE: Used in the lspcmp plugin file as well
vim.keymap.set("n", "<S-tab>", function()
    local line_num = vim.fn.line(".")
    local col_num = vim.fn.col(".")
    local line = vim.fn.getline(line_num)

    vim.api.nvim_command("normal! v<")
    if col_num < #line then
        vim.api.nvim_command("normal! hhhh")
    end
end, { noremap = true, silent = true, desc = "Shift Line Left" })

vim.keymap.set("i", "<S-tab>", function()
    local line_num = vim.fn.line(".")
    local col_num = vim.fn.col(".")
    local line = vim.fn.getline(line_num)

    vim.api.nvim_command("normal! v<")
    if col_num < #line then
        vim.api.nvim_command("normal! hhhh")
    end
end, { noremap = true, silent = true, desc = "Shift Line Left" })

vim.keymap.set("v", "<S-tab>", function()
    local ls, cs, le, ce = get_ls_cs_le_ce()
    ---@diagnostic disable-next-line: undefined-field
    local tab_width = vim.opt.tabstop:get()

    vim.api.nvim_command("normal! <")
    vim.api.nvim_command("call cursor(" .. tostring(ls) .. "," .. tostring(cs - tab_width) .. ")")
    vim.api.nvim_command("normal! v")
    vim.api.nvim_command("call cursor(" .. tostring(le) .. "," .. tostring(ce - tab_width) .. ")")
end, { noremap = true, silent = true, desc = "Shift Line Left" })

vim.keymap.set("v", "(", function()
    surround_selected("(", ")")
end)
vim.keymap.set("v", "[", function()
    surround_selected("[", "]")
end)
vim.keymap.set("v", "{", function()
    surround_selected("{", "}")
end)
vim.keymap.set("v", "<", function()
    surround_selected("<", ">")
end)
vim.keymap.set("v", '"', function()
    surround_selected('"', '"')
end)
vim.keymap.set("v", "'", function()
    surround_selected("'", "'")
end)

vim.keymap.set("n", "<CR>", function()
    local line_num = vim.fn.line(".")
    local col_num = vim.fn.col(".")
    local line_len = #vim.fn.getline(line_num)

    if col_num < line_len then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i<CR>", true, true, true), "t", true)
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("a<CR>", true, true, true), "t", true)
    end
end, { noremap = true, silent = true, desc = "New Line" })

-- local keys = "qwertyuopasdfghjkl;zxcvbnm,.QWERTYUIOPASDFGHJKLZXCVBNM?1234567890-=~!@#$%^&*_+"
-- local vis = false
--
-- for i = 1, #keys do
--     local key = keys:sub(i, i)
--
--     vim.keymap.set("v", "@" .. key, key)
--
--     vim.keymap.set("v", key, function()
--         if vis then
--             vim.api.nvim_feedkeys("@" .. key, "", true)
--         else
--             local line_start = vim.fn.line("v")
--             local line_end = vim.fn.line(".")
--             local col_start = vim.fn.col("v")
--             local col_end = vim.fn.col(".")
--
--             if line_start ~= line_end or col_start ~= col_end then
--                 delete_selected()
--
--                 vim.defer_fn(function()
--                     vim.api.nvim_feedkeys(key, "", true)
--                 end, 10)
--             end
--         end
--     end, { noremap = true, silent = true, desc = "Replace Selected With " .. key })
-- end

vim.keymap.set("v", "<CR>", function()
    local line_start = vim.fn.line("v")
    local line_end = vim.fn.line(".")
    local col_start = vim.fn.col("v")
    local col_end = vim.fn.col(".")

    if line_start ~= line_end or col_start ~= col_end then
        delete_selected()

        vim.schedule(function()
            vim.api.nvim_command("normal! o")
        end)
    end
end)

local visual_keys = {
    "$",
    "%",
    ",",
    "0",
    ";",
    "^",
    "{",
    "}",
    "b",
    "e",
    "F",
    "f",
    "G",
    "h",
    "j",
    "k",
    "l",
    "N",
    "n",
    "R",
    "r",
    "t",
    "T",
    "w",

    "[%",
    "[C",
    "[c",
    "[f",
    "[F",
    "[i",

    "]%",
    "]C",
    "]c",
    "]f",
    "]F",
    "]i",

    'i"',
    "a'",
    "a(",
    "a)",
    "a<",
    "a>",
    "a?",
    "a[",
    "a]",
    "a_",
    "a`",
    "a{",
    "a}",
    "a ",
    "aa",
    "ab",
    "aB",
    "ac",
    "ad",
    "ae",
    "af",
    "ag",
    "ai",
    "ao",
    "ap",
    "aq",
    "as",
    "at",
    "au",
    "aU",
    "aw",
    "aW",

    'al"',
    "al'",
    "al(",
    "al)",
    "al<",
    "al>",
    "al?",
    "al[",
    "al]",
    "al_",

    "al`",
    "al{",
    "al}",
    "al ",
    "ala",
    "alb",
    "alc",
    "ald",
    "ale",
    "alf",
    "alg",
    "also",
    "alq",
    "alt",
    "alu",
    "alU",

    'an"',
    "an'",
    "an(",
    "an)",
    "an<",
    "an>",
    "an?",
    "an[",
    "an]",
    "an_",
    "an`",
    "an{",
    "an}",
    "an ",
    "ana",
    "anb",
    "anc",
    "and",
    "and",
    "anf",
    "ang",
    "ano",
    "anq",
    "ant",
    "anu",
    "anU",

    "g%",
    "g[",
    "g]",
    "gc",
    "ge",
    "gg",

    'i"',
    "i'",
    "i(",
    "i)",
    "i<",
    "i>",
    "i?",
    "i[",
    "i]",
    "i_",
    "i`",
    "i{",
    "i}",
    "i ",
    "ia",
    "ib",
    "iB",
    "ic",
    "id",
    "ie",
    "if",
    "ig",
    "ii",
    "io",
    "ip",
    "iq",
    "is",
    "it",
    "iu",
    "iU",
    "iw",
    "iW",

    "il`",
    "il{",
    "il}",
    "il ",
    "ila",
    "ilb",
    "ilc",
    "ild",
    "ile",
    "ilf",
    "ilg",
    "ilo",
    "ilq",
    "ilt",
    "ilu",
    "ilU",

    'in"',
    "in'",
    "in(",
    "in)",
    "in<",
    "in>",
    "in?",
    "in[",
    "in]",
    "in_",
    "in`",
    "in{",
    "in}",
    "in ",
    "ina",
    "inb",
    "inc",
    "ind",
    "ine",
    "inf",
    "ing",
    "ino",
    "inq",
    "int",
    "inu",
    "inU",
}

-- visual_keys["$"] = "End of line"
Pasting = false
Deleting = false

vim.keymap.set("n", "pp", "p")

for _, key in pairs(visual_keys) do
    vim.keymap.set("n", "p" .. key, function()
        vim.api.nvim_feedkeys("v" .. key, "", true)

        vim.defer_fn(function()
            local line_start = vim.fn.line("v")
            local line_end = vim.fn.line(".")
            local col_start = vim.fn.col("v")
            local col_end = vim.fn.col(".")

            if line_start ~= line_end or col_start ~= col_end then
                delete_selected()

                vim.schedule(function()
                    paste()
                    vim.api.nvim_command("stopinsert")
                end)
            else
                Pasting = true
            end
        end, 10)
    end, { noremap = true, silent = true, desc = "" })
end

for _, key in pairs(visual_keys) do
    vim.keymap.set("n", "d" .. key, function()
        vim.api.nvim_feedkeys("v" .. key, "", true)

        vim.defer_fn(function()
            local line_start = vim.fn.line("v")
            local line_end = vim.fn.line(".")
            local col_start = vim.fn.col("v")
            local col_end = vim.fn.col(".")

            if line_start ~= line_end or col_start ~= col_end then
                delete_selected()

                vim.schedule(function()
                    vim.api.nvim_command("stopinsert")
                end)
            else
                Deleting = true
            end
        end, 10)
    end, { noremap = true, silent = true, desc = "" })
end

vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
        if vim.api.nvim_get_mode().mode == "v" and Pasting then
            Pasting = false

            delete_selected()

            vim.schedule(function()
                paste()
                vim.api.nvim_command("stopinsert")
            end)
        else
            if vim.api.nvim_get_mode().mode == "v" and Deleting then
                Deleting = false

                delete_selected()
                vim.schedule(function()
                    vim.api.nvim_command("stopinsert")
                end)
            end
        end
    end,
})

MultiCursor = false

local multi_cursor = function(mouse)
    if mouse then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true), "", true)
    end

    if MultiCursor then
        vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, true, true), "", true)
        end, 50)
    else
        vim.defer_fn(function()
            vim.api.nvim_command("MCunderCursor")
            MultiCursor = true
        end, 50)
    end
end

vim.keymap.set("n", "<leader>p", function()
    require("dropbar.api").pick()
end, { noremap = true, silent = true, desc = "Dropbar Expand Pick" })

vim.keymap.set("n", "<leader>n", function()
    multi_cursor(false)
end, { noremap = true, silent = true, desc = "Multi-Cursor Mode" })

vim.keymap.set("n", "<A-MiddleMouse>", function()
    multi_cursor(true)
end, { noremap = true, silent = true, desc = "Multi-Cursor Mode" })

vim.keymap.set("n", "<esc>", function()
    MultiCursor = false
    Pasting = false
    vim.api.nvim_command("nohlsearch")
end, { noremap = true, silent = true, desc = "Multi-Cursor Mode" })
