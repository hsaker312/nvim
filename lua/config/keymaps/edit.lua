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

    local isN = vim.api.nvim_get_mode().mode == "n"
    vim.api.nvim_command("normal! x")

    vim.schedule(function()
        vim.fn.setreg('"', reg1)
        vim.fn.setreg("+", reg2)

        if not isN then
            if vim.api.nvim_get_mode().mode == "n" then
                if ce >= linelen then
                    vim.api.nvim_command("startinsert!")
                else
                    vim.api.nvim_command("startinsert")
                end
            end
        end
    end)
end

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

    local ls, cs, le, ce = get_ls_cs_le_ce()
    local lines = vim.fn.getreg(reg) .. "\n"
    local lines_count = 0
    local last_line_len = 0
    local empty_line = #vim.fn.getline(ls) == 0

    for line in lines:gmatch("[^\n]*\n") do
        lines_count = lines_count + 1
        last_line_len = #line
    end

    lines_count = lines_count - 1

    if lines_count < 1 then
        if cs == 1 then
            vim.api.nvim_command("normal! P")
            vim.api.nvim_command("normal! l")

            if empty_line then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<right>", true, true, true), "", true)
            end
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

        vim.api.nvim_command("call cursor(" .. tostring(ls + lines_count) .. "," .. tostring(last_line_len) .. ")")
    end
end

local wrap_selected = function(reg, open, close)
    surround_selected(open, close)

    vim.defer_fn(function()
        vim.api.nvim_command("normal! o")
        vim.api.nvim_command('normal! "ay')
        vim.api.nvim_command("normal! h")
        vim.api.nvim_command('normal! "' .. reg .. "P")
    end, 30)
end

vim.keymap.set("i", "<a-w>", "<up>", { noremap = true, silent = true, desc = "Select line" })
vim.keymap.set("i", "<a-a>", "<left>", { noremap = true, silent = true, desc = "Select line" })
vim.keymap.set("i", "<a-s>", "<down>", { noremap = true, silent = true, desc = "Select line" })
vim.keymap.set("i", "<a-d>", "<right>", { noremap = true, silent = true, desc = "Select line" })
vim.keymap.set("i", "<a-q>", "<home>", { noremap = true, silent = true, desc = "Select line" })
vim.keymap.set("i", "<a-e>", "<end>", { noremap = true, silent = true, desc = "Select line" })

vim.keymap.set("n", "V", "_vg_", { noremap = true, silent = true, desc = "Select line" })
vim.keymap.set("n", "M", function()
    vim.ui.input({ prompt = "Delete Mark" }, function(value)
        if value == nil then
            return
        end

        if value == '"' then
            value = "\\" .. value
        end

        vim.cmd("delmarks " .. value)
    end)
end, { noremap = true, silent = true, desc = "Select line" })

vim.keymap.set("v", "<Del>", delete_selected, { noremap = true, silent = true, desc = "Delete Selected" })
vim.keymap.set("n", "<Del>", delete_selected, { noremap = true, silent = true, desc = "Delete Selected" })

vim.keymap.set("n", "<C-x>", "V<Del>", { noremap = true, silent = true, desc = "Cut Line" })
vim.keymap.set("i", "<C-x>", "<esc>V<Del>", { noremap = true, silent = true, desc = "Cut Line" })
vim.keymap.set("v", "<C-x>", "<Del>i", { noremap = true, silent = true, desc = "Cut Selected" })

vim.keymap.set({ "n", "i" }, "<C-c>", "<esc>", { noremap = true, silent = true, desc = "Copy Line" })
vim.keymap.set("v", "<C-c>", '"+y<esc>gv', { noremap = true, silent = true, desc = "Copy Selected" })

local function setreg(reg)
    vim.ui.input({}, function(input)
        vim.fn.setreg(reg, input)
    end)
end
vim.keymap.set("v", "<leader>0", '"0ygv', { noremap = true, silent = true, desc = "Copy To Reg 0" })
vim.keymap.set("v", "<leader>1", '"1ygv', { noremap = true, silent = true, desc = "Copy To Reg 1" })
vim.keymap.set("v", "<leader>2", '"2ygv', { noremap = true, silent = true, desc = "Copy To Reg 2" })
vim.keymap.set("v", "<leader>3", '"3ygv', { noremap = true, silent = true, desc = "Copy To Reg 3" })
vim.keymap.set("v", "<leader>4", '"4ygv', { noremap = true, silent = true, desc = "Copy To Reg 4" })
vim.keymap.set("v", "<leader>5", '"5ygv', { noremap = true, silent = true, desc = "Copy To Reg 5" })

vim.keymap.set("n", "<leader>0", function()
    setreg("0")
end, { noremap = true, silent = true, desc = "Set Reg 0" })
vim.keymap.set("n", "<leader>1", function()
    setreg("1")
end, { noremap = true, silent = true, desc = "Copy To Reg 1" })
vim.keymap.set("n", "<leader>2", function()
    setreg("2")
end, { noremap = true, silent = true, desc = "Copy To Reg 2" })
vim.keymap.set("n", "<leader>3", function()
    setreg("3")
end, { noremap = true, silent = true, desc = "Copy To Reg 3" })
vim.keymap.set("n", "<leader>4", function()
    setreg("4")
end, { noremap = true, silent = true, desc = "Copy To Reg 4" })
vim.keymap.set("n", "<leader>5", function()
    setreg("5")
end, { noremap = true, silent = true, desc = "Copy To Reg 5" })

vim.keymap.set("n", "<C-v>", function()
    local col_num = vim.fn.col(".")
    local line_num = vim.fn.line(".")

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

vim.keymap.set("i", "<A-right>", function()
    local line_num = vim.fn.line(".")
    local col_num = vim.fn.col(".")
    local line = vim.fn.getline(line_num)

    vim.api.nvim_command("normal! v>")
    if col_num < #line then
        vim.api.nvim_command("normal! llll")
    end
end, { noremap = true, silent = true, desc = "Shift Line Right" })

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

vim.keymap.set("i", "<A-left>", function()
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

vim.keymap.set("n", "<A-/>", function()
    vim.api.nvim_feedkeys("gcc", "", true)
end, { noremap = true, silent = true, desc = "Comment Line" })

vim.keymap.set("i", "<A-/>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>gccji", true, true, true), "", true)
end, { noremap = true, silent = true, desc = "Comment Line" })

vim.keymap.set("v", "<A-/>", function()
    vim.api.nvim_feedkeys("gc", "", true)
end, { noremap = true, silent = true, desc = "Comment Selected" })

for i = 0, 5, 1 do
    vim.keymap.set("v", "<leader>(" .. i, function()
        wrap_selected(tostring(i), "(", ")")
    end, { noremap = true, silent = true, desc = "Wrap highlight with " .. i .. "register()" })

    vim.keymap.set("v", "<leader>[" .. i, function()
        wrap_selected(tostring(i), "[", "]")
    end, { noremap = true, silent = true, desc = "Wrap highlight with " .. i .. "register[]" })

    vim.keymap.set("v", "<leader>{" .. i, function()
        wrap_selected(tostring(i), "{", "}")
    end, { noremap = true, silent = true, desc = "Wrap highlight with " .. i .. "register{}" })

    vim.keymap.set("v", "<leader>>" .. i, function()
        wrap_selected(tostring(i), "<", ">")
    end, { noremap = true, silent = true, desc = "Wrap highlight with " .. i .. "register<>" })

    vim.keymap.set("v", '<leader>"' .. i, function()
        wrap_selected(tostring(i), '"', '"')
    end, { noremap = true, silent = true, desc = "Wrap highlight with " .. i .. 'register""' })

    vim.keymap.set("v", "<leader>'" .. i, function()
        wrap_selected(tostring(i), "'", "'")
    end, { noremap = true, silent = true, desc = "Wrap highlight with " .. i .. "register''" })
end

vim.keymap.set("n", "<c-T>", "<CR>")
vim.keymap.set("n", "<CR>", function()
    local buf = vim.api.nvim_get_current_buf()

    local mod = vim.api.nvim_get_option_value("modifiable", {
        buf = buf,
    })

    if mod == true then
        local line_num = vim.fn.line(".")
        local col_num = vim.fn.col(".")
        local line_len = #vim.fn.getline(line_num)

        if col_num < line_len then
            vim.cmd('execute "normal! a\r"')
            vim.cmd("startinsert")
            vim.cmd("normal! l")
        else
            vim.cmd('execute "normal! a\r"')
            vim.cmd("startinsert")
        end
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<c-T>", true, true, true), "", true)
    end

end, { noremap = true, silent = true, desc = "New Line" })

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

vim.keymap.set("n", "<leader>y", function()
    if vim.g.windows then
        local str = vim.fn.getreg("+")
        vim.cmd("set shell=cmd")
        local c = "!ssh -i ~/.ssh/linux-pc -p 2277 helmy@192.168.0.3 \"echo '" .. str .. "' | wl-copy 2>/dev/null\""
        print(c)
        vim.cmd(c)
    end
end)
