M = {}

local prefix = "maven-tools."

---@type Config
local config = require(prefix .. "config.config")

---@type Utils
local utils = require(prefix .. "utils")

-- local my_require = require
--
-- require = function(str)
--     if str:match("^Xml") then
--         my_require(prefix .. "dep.xml2lua." .. str)
--     else
--         my_require(str)
--     end
-- end
--

--
---@type Runner
local runner = require(prefix .. "maven.runner")

---@type Importer
local maven_importer = require(prefix .. "maven.importer")

local main_win = vim.api.nvim_get_current_win()
local maven_win = nil

---@type table<integer,fun():boolean>
local line_callback = {}

---@type table<integer,integer?>
local line_range = {}

---@class Line_Root
---@field first integer
---@field last integer
---@field item Tree_Entry

---@type Line_Root[]
local line_roots = {}
local maven_buf = nil

---@type table<"0"|"1"|"2",fun(Tree_Entry):fun():boolean>
local callback_makers = {
    ---@param item Tree_Entry
    ---@return function
    ["0"] = function(item)
        return function()
            item.expanded = not item.expanded
            return true
        end
    end,
    ["1"] = function(item)
        ---@param entry Tree_Entry
        return function(entry)
            -- local task = require("overseer").new_task({
            --     cmd = "mvn",
            --     args = { "-f", item.file, item.command },
            --     components = {
            --         { "on_output_quickfix", open = true, set_diagnostics = true },
            --         "default",
            --     },
            -- })

            runner.run(item, maven_importer.Maven_Info_Pom_File[tostring(entry.info)])

            return false
        end
    end,
    ["2"] = function(_)
        return function()
            return false
        end
    end,
}

---@param item Tree_Entry
---@return fun():boolean
local make_tree_callback = function(item)
    return callback_makers[item.callback](item)
end

local filter = ""

local function create_tree_buffer()
    line_callback = {}
    line_range = {}
    line_roots = {}

    local buf = vim.api.nvim_create_buf(false, true)
    local lines = utils.Array()

    ---@class Highlight
    ---@field highlight string
    ---@field line_num integer
    ---@field col_begin integer
    ---@field col_end integer

    ---@type Highlight[]
    local highlights = {}

    local header = " " .. "Maven"

    table.insert(highlights, {
        highlight = "@label",
        line_num = lines:size(),
        col_begin = 0,
        col_end = #header,
    })

    if not maven_importer.idle() then
        local progress = " (importing " .. tostring(maven_importer.progress()):gsub("%.%d+", "") .. "%)"

        table.insert(highlights, {
            highlight = "@comment",
            line_num = lines:size(),
            col_begin = #header,
            col_end = #header + #progress,
        })

        header = header .. progress
    end

    lines:append(header)
    line_range[1] = nil

    table.insert(line_callback, function()
        return false
    end)

    ---@param children Tree_Entry[]
    ---@param tab string
    local function append_children(children, tab)
        local current_tab = tab .. "   "

        for _, child in pairs(children) do
            if child.children[1] ~= nil or child.show_always then
                local line = current_tab

                if child.children[1] ~= nil then
                    if child.expanded then
                        line = line .. " "
                    else
                        line = line .. " "
                    end

                    table.insert(highlights, {
                        highlight = "@SignColomn",
                        line_num = lines:size(),
                        col_begin = 0,
                        col_end = #line,
                    })
                else
                    line = line .. "  "
                end

                for i, text_obj in ipairs(child.text_objs) do
                    line = line .. text_obj.text

                    if i == 1 then
                        line_range[lines:size() + 1] = #line
                    end

                    table.insert(highlights, {
                        highlight = text_obj.hl,
                        line_num = lines:size(),
                        col_begin = #line - #text_obj.text,
                        col_end = #line,
                    })
                end

                lines:append(line)

                table.insert(line_callback, make_tree_callback(child))

                if child.children[1] ~= nil and child.expanded then
                    append_children(child.children, current_tab)
                end
            end
        end
    end

    ---@param modules Tree_Entry
    ---@param tab string
    ---@return boolean
    local function append_modules(modules, tab)
        if modules == nil then
            return false
        end

        local current_tab = tab .. "   "

        local line = current_tab

        if modules.expanded then
            line = line .. " "
        else
            line = line .. " "
        end

        table.insert(highlights, {
            highlight = "@SignColomn",
            line_num = lines:size(),
            col_begin = 0,
            col_end = #line,
        })

        for i, text_obj in ipairs(modules.text_objs) do
            line = line .. text_obj.text

            if i == 1 then
                line_range[lines:size() + 1] = #line
            end

            table.insert(highlights, {
                highlight = text_obj.hl,
                line_num = lines:size(),
                col_begin = #line - #text_obj.text,
                col_end = #line,
            })
        end

        lines:append(line)

        table.insert(line_callback, make_tree_callback(modules))

        if modules.expanded then
            for _, module in pairs(modules.children) do
                local start_line = lines:size() + 1

                append_children({ module }, current_tab)

                if module.expanded then
                    append_modules(module.modules, current_tab .. "   ")
                end

                table.insert(line_roots, { first = start_line, last = lines:size(), item = module })
            end
        end

        return true
    end

    for _, file in ipairs(maven_importer.pom_files) do
        local item = nil

        if
            maven_importer.Pom_File_Maven_Info[file] ~= nil
            and maven_importer.Pom_File_Maven_Info[file].info ~= nil
            and maven_importer.Maven_Entries[tostring(maven_importer.Pom_File_Maven_Info[file].info)] ~= nil
        then
            item = maven_importer.Maven_Entries[tostring(maven_importer.Pom_File_Maven_Info[file].info)]
        elseif maven_importer.Maven_Entries[file] ~= nil then
            item = maven_importer.Maven_Entries[file]
        end

        if item ~= nil and tostring(item.info):match(filter) then
            ---@cast item Tree_Entry
            if item.module == 0 then
                local line = ""

                if item.children[1] ~= nil then
                    if item.expanded then
                        line = " "
                    else
                        line = " "
                    end
                else
                    line = "  "
                end

                table.insert(highlights, {
                    highlight = "@SignColomn",
                    line_num = lines:size(),
                    col_begin = 0,
                    col_end = #line,
                })

                for i, text_obj in ipairs(item.text_objs) do
                    line = line .. text_obj.text

                    if i == 1 then
                        line_range[lines:size() + 1] = #line
                    end

                    table.insert(highlights, {
                        highlight = text_obj.hl,
                        line_num = lines:size(),
                        col_begin = #line - #text_obj.text,
                        col_end = #line,
                    })
                end

                local start_line = lines:size()
                lines:append(line)
                local end_line = lines:size()

                table.insert(line_callback, make_tree_callback(item))

                if item.expanded then
                    append_children(item.children, "")

                    end_line = lines:size()

                    if append_modules(item.modules, "") then
                        end_line = end_line + 1
                    end
                end

                table.insert(line_roots, { first = start_line, last = lines:size(), item = item })
            end
        end
    end

    if lines:size() < 2 then
        local line = "(No POM Files found)"

        table.insert(highlights, {
            highlight = "@comment",
            line_num = lines:size(),
            col_begin = 0,
            col_end = #line,
        })

        lines:append(line)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines:values())

    vim.api.nvim_set_option_value("modifiable", false, {
        buf = buf,
    })

    vim.api.nvim_set_option_value("buftype", "nofile", {
        buf = buf,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "r", "<Cmd>lua M.test()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "p", "<Cmd>lua M.open_pom_file()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "e", "<Cmd>lua M.show_error()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "<C-f>", "<Cmd>lua M.filter()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "s", "<Cmd>lua M.show_effective_pom()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<Cmd>lua M.toggle_item()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "<2-LeftMouse>", "<Cmd>lua M.toggle_item()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Cmd>quit<CR>", {
        noremap = true,
        silent = true,
    })

    for _, highlight in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(
            buf,
            -1,
            highlight.highlight,
            highlight.line_num,
            highlight.col_begin,
            highlight.col_end
        )
    end

    return buf
end

local function create_tree_window(buf)
    local win = vim.api.nvim_open_win(buf, true, {
        split = "right",
        win = -1,
        -- relative = "editor",
        width = 40,
        -- height = 10,
        -- row = 1,
        -- col = vim.api.nvim_get_option("columns") - 20,
        -- style = "minimal",
        -- border = "single"
    })

    vim.api.nvim_set_option_value("number", false, {
        win = win,
    })

    vim.api.nvim_set_option_value("spell", false, {
        win = win,
    })

    return win
end

M.show_win = function()
    if maven_win == nil and maven_buf ~= nil then
        maven_win = create_tree_window(maven_buf)
    end
end

local function update_buf()
    maven_buf = create_tree_buffer()
    local line = vim.fn.line(".")
    local col = vim.fn.col(".")

    if maven_win ~= nil then
        vim.api.nvim_win_set_buf(maven_win, maven_buf)
    end

    if maven_win ~= nil then
        if vim.api.nvim_get_current_win() == maven_win then
            pcall(function()
                vim.api.nvim_win_set_cursor(maven_win, { line, col - 1 })
            end)
        end
    end
end

M.update_test = update_buf

M.test = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            maven_importer.refresh_entry(v.item)
            break
        end
    end
end

M.open_pom_file = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            -- local mods = v.item.modules
            -- if mods == nil then
            --     return
            -- end
            --
            -- for _, x in pairs(mods.children) do
            --     print(tostring(x.info))
            -- end
            --
            local file = maven_importer.Maven_Info_Pom_File[tostring(v.item.info)] or v.item.file

            if file ~= nil then
                local file_buf = utils.get_file_buffer(file)

                if file_buf == nil then
                    -- vim.api.nvim_set_current_win(main_win)

                    vim.api.nvim_win_call(main_win, function()
                        vim.api.nvim_command("edit " .. file)
                    end)
                else
                    -- vim.api.nvim_set_current_win(main_win)
                    vim.api.nvim_win_set_buf(main_win, file_buf)
                end
            end

            -- vim.api.nvim_buf_call(runner_buf_id, function()
            --     vim.cmd("normal! G")
            -- end)
            --
            -- if file_buf == nil then
            --     vim.api.nvim_set_current_win(main_win_id)
            --     vim.api.nvim_command("edit " .. file)
            -- else
            --     vim.api.nvim_set_current_win(main_win_id)
            --     vim.api.nvim_win_set_buf(main_win_id, file_buf)
            -- end
            --
            -- vim.api.nvim_win_set_buf(main_win)
            -- vim.api.nvim_command("edit " .. maven_importer.Maven_Info_Pom_File[tostring(v.item.info)])
            -- print(tostring(v.item.info), maven_importer.Maven_Info_Pom_File[tostring(v.item.info)])
            break
        end
    end
end

M.show_error = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            if v.item.file ~= nil then
                print(maven_importer.Pom_File_Error[v.item.file])
            end
            break
        end
    end
end

M.show_effective_pom = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            Importer.effective_pom(v.item, function (effective_pom)
                local buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(effective_pom, "\n"))
                vim.api.nvim_win_set_buf(main_win, buf)
                vim.api.nvim_buf_call(buf, function ()
                    vim.api.nvim_command("setfiletype xml")
                end)
            end)
            break
        end
    end
end

function M.filter()
    filter = vim.fn.input("Filter: ")
    update_buf()
end

-- Function to toggle expand/collapse
function M.toggle_item()
    local line = vim.fn.line(".")
    local col = vim.fn.col(".")

    local entry

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            entry = v.item
            break
        end
    end

    if type(line_callback[line]) == "function" then
        if line_callback[line](entry) then
            update_buf()
        end

        if maven_win ~= nil then
            vim.api.nvim_win_set_cursor(maven_win, { line, col - 1 })
        end
    end
end

-- Function to toggle expand/collapse
-- function M.toggle_item_at(index)
--     tree[index].expanded = not tree[index].expanded
--     -- Update the tree buffer content
--     local buf = create_tree_buffer()
--     -- Get the current window and update its buffer
--     local win = vim.api.nvim_get_current_win()
--     vim.api.nvim_win_set_buf(win, buf)
--
--     vim.api.nvim_command('syntax region @label start="" end=" "')
--     vim.api.nvim_command('syntax region @label start="" end="$"')
-- end
--
--
local function toggle()
    main_win = vim.api.nvim_get_current_win()
    maven_buf = create_tree_buffer()
    maven_win = create_tree_window(maven_buf)
    -- maven_importer.make_tree_mp(update_buf)
    -- maven_importer.process_pom_files("/home/helmy/ssd/1tbnvmebackup/work/atoms-software-suite", update_buf)

    maven_importer.process_pom_files(vim.loop.cwd(), update_buf)

    vim.api.nvim_create_autocmd("CursorMoved", {
        callback = function()
            if maven_win ~= nil then
                if vim.api.nvim_get_current_win() == maven_win then
                    local line = vim.fn.line(".")
                    local col = vim.fn.col(".")

                    if line_range[line] == nil then
                        if vim.api.nvim_buf_line_count(maven_buf) > line and line_range[line + 1] ~= nil then
                            vim.api.nvim_win_set_cursor(maven_win, { line + 1, line_range[line + 1] })
                        end
                    else
                        if line_range[line] ~= nil then
                            if col <= line_range[line] then
                                vim.api.nvim_win_set_cursor(maven_win, { line, line_range[line] })
                            end
                        end
                    end
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWinEnter", {
        callback = function()
            if maven_win ~= nil then
                local new_buf = vim.api.nvim_win_get_buf(maven_win)
                if new_buf ~= maven_buf then
                    vim.schedule(function()
                        vim.api.nvim_win_set_buf(maven_win, maven_buf)
                        vim.api.nvim_win_set_buf(main_win, new_buf)
                    end)
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(event)
            if maven_win ~= nil then
                if tonumber(event.match) == maven_win then
                    maven_win = nil
                end
            end
        end,
    })

    vim.api.nvim_create_user_command("MavenShow", M.show_win, {})
end

function M.setup()
    vim.api.nvim_create_user_command("MavenToolsToggle", toggle, {})
end

return M
