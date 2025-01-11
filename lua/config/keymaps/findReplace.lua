Current_find_str = ""

vim.api.nvim_create_autocmd({ "CmdlineLeave" }, {
    callback = function()
        if vim.fn.getcmdtype() == "/" then
            local line = vim.fn.getcmdline()
            if line:sub(0, 2) == "\\C" then
                Current_find_str = line:sub(3, #line)
            else
                Current_find_str = line
            end
        end
    end,
})

local find_selected = function(case)
    local isVisualMode = vim.fn.mode():find("[Vv]")

    if not isVisualMode then
        return
    end

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

        selected_text = selected_text .. line_text:sub(start_col, end_col):gsub("([$^%.%*\\%[%]~])", "\\%1")
        if line ~= le then
            selected_text = selected_text .. "\\n"
        end
    end

    -- print(selected_text)

    Current_find_str = selected_text

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "", true)
    if case then
        vim.api.nvim_feedkeys("/\\C", "", true)
    else
        vim.api.nvim_feedkeys("/", "", true)
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(selected_text, true, true, true), "", true)
end

local replace_selected = function()
    local isVisualMode = vim.fn.mode():find("[Vv]")
    if not isVisualMode then
        return
    end

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

        selected_text = selected_text .. line_text:sub(start_col, end_col):gsub("([$^%.%*\\%[%]~])", "\\%1")
        if line ~= le then
            selected_text = selected_text .. "\\n"
        end
    end

    -- print(selected_text)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "", true)
    vim.api.nvim_feedkeys(":%s/", "", true)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(selected_text, true, true, true), "", true)
    vim.api.nvim_feedkeys("//g", "", true)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<left><left>", true, true, true), "", true)
end

vim.keymap.set("n", "<C-f>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("/<up>", true, true, true), "", true)
end, { noremap = true, silent = true, desc = "Find" })

vim.keymap.set("i", "<C-f>", "<cmd>normal! /<cr>", { noremap = true, silent = true, desc = "Find" })

vim.keymap.set("v", "<C-f>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("*", true, true, true), "", true)
end, { noremap = true, silent = true, desc = "Find" })

vim.keymap.set("n", "<A-C-f>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("?<up>", true, true, true), "", true)
end, { noremap = true, silent = true, desc = "Find" })

vim.keymap.set("i", "<A-C-f>", "<cmd>normal! ?<cr>", { noremap = true, silent = true, desc = "Find" })

vim.keymap.set("v", "<A-C-f>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("#", true, true, true), "", true)
end, { noremap = true, silent = true, desc = "Find" })

vim.keymap.set(
    "v",
    "<A-C-r>",
    replace_selected,
    { noremap = true, silent = true, desc = "Replace All Occurrences of Selected" }
)
