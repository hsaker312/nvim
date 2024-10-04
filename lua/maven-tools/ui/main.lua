---@class Line_Root
---@field first integer
---@field last integer
---@field item Tree_Entry

---@class Highlight
---@field highlight string
---@field line_num integer
---@field col_begin integer
---@field col_end integer

---@class Maven_Main_Window
Maven_Main_Window = {}

local prefix = "maven-tools."

---@type Maven_Console_Window
local console = require("maven-tools.ui.console")

---@type Config
local config = require(prefix .. "config.config")

---@type Utils
local utils = require(prefix .. "utils")

---@type Maven_Importer
local maven_importer = require(prefix .. "maven.importer")

---@type Maven_Runner
local runner = require(prefix .. "maven.runner")

---@type integer|nil
local maven_win = nil

---@type integer|nil
local maven_buf = nil

---@type table<integer,fun(entry:Tree_Entry):boolean>
local line_callback = {}

---@type table<integer,integer?>
local line_range = {}

---@type Line_Root[]
local line_roots = {}

---@type integer[]
local autocmds = {}

---@type string
local filter = config.default_filter

---@type boolean
local show_all = false

---@type table<"0"|"1"|"2",fun(entry:Tree_Entry):fun():boolean>
local entry_callback_map = {
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
            runner.run(
                item,
                maven_importer.Maven_Info_Pom_File[tostring(entry.info)],
                console.console_reset,
                console.console_append
            )

            return false
        end
    end,
    ["2"] = function(_)
        return function()
            return false
        end
    end,
}

---@param win integer
local function set_main_window_options(win)
    vim.api.nvim_set_option_value("number", false, {
        win = win,
    })

    vim.api.nvim_set_option_value("spell", false, {
        win = win,
    })
end

---@param buf integer
---@return integer
local function create_main_window(buf)
    local win = vim.api.nvim_open_win(buf, true, {
        split = "right",
        win = -1,
        width = 40,
    })

    set_main_window_options(win)

    return win
end

---@param buf integer
local function set_main_buffer_options(buf)
    vim.api.nvim_set_option_value("modifiable", false, {
        buf = buf,
    })

    vim.api.nvim_set_option_value("buftype", "nofile", {
        buf = buf,
    })

    vim.api.nvim_set_option_value("swapfile", false, {
        buf = buf,
    })
end

---@param buf integer
local function set_main_buffer_keymaps(buf)
    -- vim.api.nvim_buf_set_keymap(buf, "n", "r", "<Cmd>lua M.test()<CR>", {
    --     noremap = true,
    --     silent = true,
    -- })
    --
    -- vim.api.nvim_buf_set_keymap(buf, "n", "p", "<Cmd>lua M.open_pom_file()<CR>", {
    --     noremap = true,
    --     silent = true,
    -- })
    --
    -- vim.api.nvim_buf_set_keymap(buf, "n", "e", "<Cmd>lua M.show_error()<CR>", {
    --     noremap = true,
    --     silent = true,
    -- })
    --
    vim.api.nvim_buf_set_keymap(buf, "n", "<C-f>", "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".filter()<CR>", {
        noremap = true,
        silent = true,
    })
    --
    -- vim.api.nvim_buf_set_keymap(buf, "n", "s", "<Cmd>lua M.show_effective_pom()<CR>", {
    --     noremap = true,
    --     silent = true,
    -- })
    --
    vim.api.nvim_buf_set_keymap(
        buf,
        "n",
        "<CR>",
        "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".toggle_item()<CR>",
        {
            noremap = true,
            silent = true,
        }
    )

    vim.api.nvim_buf_set_keymap(buf, "n", "r", "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".run()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(
        buf,
        "n",
        "ds",
        "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_sources()<CR>",
        {
            noremap = true,
            silent = true,
        }
    )

    vim.api.nvim_buf_set_keymap(
        buf,
        "n",
        "dd",
        "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_documentation()<CR>",
        {
            noremap = true,
            silent = true,
        }
    )

    vim.api.nvim_buf_set_keymap(
        buf,
        "n",
        "da",
        "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_sources_and_documentation()<CR>",
        {
            noremap = true,
            silent = true,
        }
    )

    vim.api.nvim_buf_set_keymap(buf, "n", "h", "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".toggle_hide()<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "H", "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_all()<CR>", {
        noremap = true,
        silent = true,
    })
    --
    -- vim.api.nvim_buf_set_keymap(buf, "n", "<2-LeftMouse>", "<Cmd>lua M.toggle_item()<CR>", {
    --     noremap = true,
    --     silent = true,
    -- })
    --
    -- vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Cmd>quit<CR>", {
    --     noremap = true,
    --     silent = true,
    -- })
end

---@param buf integer
---@param highlights Highlight[]
local function set_main_buffer_highlights(buf, highlights)
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
end

---@param item Tree_Entry
---@return fun():boolean
local make_entry_callback = function(item)
    return entry_callback_map[item.callback](item)
end

---@param lines Array
---@param highlights Highlight[]
local function create_header(lines, highlights)
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

    for i = 1, lines:size(), 1 do
        line_range[i] = nil
    end

    table.insert(line_callback, function()
        return false
    end)
end

---@param lines Array
---@param highlights Highlight[]
---@param filter_enabled boolean
local function create_footer(lines, highlights, filter_enabled)
    local line

    if filter_enabled then
        line = "(No Match Found)"
    else
        line = "(No POM Files found)"
    end

    table.insert(highlights, {
        highlight = "@comment",
        line_num = lines:size(),
        col_begin = 0,
        col_end = #line,
    })

    lines:append(line)

    line_range[lines:size()] = 0

    table.insert(line_callback, function()
        return false
    end)
end

---@param item Tree_Entry
---@return boolean
local function filter_match(item)
    local info = tostring(item.info)

    if info:len() > 2 then
        if info:match(filter) ~= nil then
            return true
        end
    end

    for _, text_obj in ipairs(item.text_objs) do
        if text_obj.text:len() > 2 then
            if text_obj.text:match(filter) ~= nil then
                return true
            end
        end
    end

    return false
end

---@param children Tree_Entry[]
---@param tab string
---@param lines Array
---@param highlights Highlight[]
local function append_children(children, tab, lines, highlights)
    local current_tab = tab

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

            table.insert(line_callback, make_entry_callback(child))

            if child.children[1] ~= nil and child.expanded then
                append_children(child.children, current_tab .. config.tab, lines, highlights)
            end
        end
    end
end

---@param modules Tree_Entry
---@param tab string
---@param lines Array
---@param highlights Highlight[]
---@param filter_enabled boolean
---@param sub_module boolean
---@return boolean
local function append_modules(modules, tab, lines, highlights, filter_enabled, sub_module)
    if modules == nil then
        return false
    end

    for _, module in pairs(modules.children) do
        local start_line = lines:size() + 1

        local show_module = ((sub_module or not filter_enabled) and (module.hide == nil or show_all))
            or (filter_enabled and filter_match(module))

        if show_module then
            append_children(
                { module },
                (filter_enabled and not sub_module) and tab or tab .. config.tab,
                lines,
                highlights
            )
        end

        if module.expanded or filter_enabled then
            append_modules(
                module.modules,
                filter_enabled and tab or tab .. config.tab,
                lines,
                highlights,
                filter_enabled,
                show_module and module.expanded == true
            )
        end

        table.insert(line_roots, { first = start_line, last = lines:size(), item = module })
    end

    -- local current_tab = tab

    -- local line = current_tab

    -- if modules.expanded then
    --     line = line .. " "
    -- else
    --     line = line .. " "
    -- end

    -- table.insert(highlights, {
    --     highlight = "@SignColomn",
    --     line_num = lines:size(),
    --     col_begin = 0,
    --     col_end = #line,
    -- })

    -- for i, text_obj in ipairs(modules.text_objs) do
    --     line = line .. text_obj.text
    --
    --     if i == 1 then
    --         line_range[lines:size() + 1] = #line
    --     end
    --
    --     table.insert(highlights, {
    --         highlight = text_obj.hl,
    --         line_num = lines:size(),
    --         col_begin = #line - #text_obj.text,
    --         col_end = #line,
    --     })
    -- end

    -- lines:append(line)

    -- table.insert(line_callback, make_entry_callback(modules))

    -- if modules.expanded then
    -- end

    return true
end

---@return Array
---@return Highlight[]
local function generate_main_buffer_lines()
    local lines = utils.Array()

    ---@type Highlight[]
    local highlights = {}

    local filter_enabled = filter:len() > 0

    create_header(lines, highlights)

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

        if item ~= nil then
            local start_line = lines:size()

            ---@cast item Tree_Entry
            if item.module == 0 then
                local matched_item = (item.hide == nil or show_all)

                if filter_enabled then
                    matched_item = filter_match(item)
                end

                if matched_item then
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

                    lines:append(line)
                    -- local end_line = lines:size()

                    table.insert(line_callback, make_entry_callback(item))
                end

                if item.expanded and matched_item then
                    append_children(item.children, config.tab, lines, highlights)
                    append_modules(item.modules, "", lines, highlights, filter_enabled, true)
                    -- end_line = lines:size()

                    -- if append_modules(item.modules, "", lines, highlights) then
                    -- end_line = end_line + 1
                    -- end
                elseif filter_enabled then
                    append_modules(item.modules, "", lines, highlights, filter_enabled, false)
                end

                table.insert(line_roots, { first = start_line, last = lines:size(), item = item })
            end
        end
    end

    if lines:size() < 2 then
        create_footer(lines, highlights, filter_enabled)
    end

    return lines, highlights
end

local function create_main_buffer()
    line_callback = {}
    line_range = {}
    line_roots = {}

    local buf = vim.api.nvim_create_buf(false, true)

    local lines, highlights = generate_main_buffer_lines()

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines:values())

    set_main_buffer_options(buf)
    set_main_buffer_keymaps(buf)
    set_main_buffer_highlights(buf, highlights)

    return buf
end

local function update_main_buffer()
    maven_buf = create_main_buffer()
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

local function main_window_close_handler()
    maven_buf = nil
    maven_win = nil

    for _, autocmd in ipairs(autocmds) do
        vim.api.nvim_del_autocmd(autocmd)
    end

    autocmds = {}
end

local function initialize_autocmds()
    table.insert(
        autocmds,
        vim.api.nvim_create_autocmd("CursorMoved", {
            callback = function()
                if maven_win ~= nil and maven_buf ~= nil then
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
    )

    table.insert(
        autocmds,
        vim.api.nvim_create_autocmd("BufWinEnter", {
            callback = function()
                if maven_win ~= nil and maven_buf ~= nil then
                    local new_buf = vim.api.nvim_win_get_buf(maven_win)

                    if new_buf ~= maven_buf then
                        vim.schedule(function()
                            vim.api.nvim_win_set_buf(maven_win, maven_buf)

                            local editor_win = utils.get_editor_window()

                            if editor_win ~= nil then
                                vim.api.nvim_win_set_buf(editor_win, new_buf)
                            end
                        end)
                    end
                end
            end,
        })
    )

    table.insert(
        autocmds,
        vim.api.nvim_create_autocmd("WinClosed", {
            callback = function(event)
                if maven_win ~= nil then
                    if tonumber(event.match) == maven_win then
                        main_window_close_handler()
                    end
                end
            end,
        })
    )
end

function Maven_Main_Window:start()
    maven_buf = create_main_buffer()
    maven_win = create_main_window(maven_buf)
    local cwd = vim.uv.cwd()

    if cwd ~= nil then
        vim.schedule(function()
            maven_importer.process_pom_files(cwd, update_main_buffer)
        end)
    end

    vim.api.nvim_create_user_command("MavenHideConsole", console.hide, {})

    initialize_autocmds()
end

function Maven_Main_Window.toggle_item()
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
            update_main_buffer()
        end

        if maven_win ~= nil then
            vim.api.nvim_win_set_cursor(maven_win, { line, col - 1 })
        end
    end
end

function Maven_Main_Window.filter()
    filter = vim.fn.input("Filter: " .. filter)

    update_main_buffer()
end

---@return Tree_Entry|nil
local function get_current_entry()
    local line = vim.fn.line(".")

    for _, line_root in ipairs(line_roots) do
        if line >= line_root.first and line <= line_root.last then
            return line_root.item
        end
    end
end

---@param entry Tree_Entry
---@param targets string[]|nil
---@param items string[]|nil
---@return string[], string[]
local function get_entry_targets(entry, targets, items)
    if targets == nil then
        targets = {}
    end

    if items == nil then
        items = {}
    end

    if entry.command ~= nil then
        table.insert(targets, entry.command)
        local text = ""

        for _, text_obj in pairs(entry.text_objs) do
            text = text .. text_obj.text
        end

        table.insert(items, text)
    end

    for _, child in pairs(entry.children) do
        get_entry_targets(child, targets, items)
    end

    return targets, items
end

function Maven_Main_Window.run()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    local targets, items = get_entry_targets(entry)

    vim.ui.select(items, {
        prompt = "Run (" .. entry.text_objs[2].text .. ")",
    }, function(item, idx)
        print(item, idx)
    end)
end

function Maven_Main_Window.download_sources()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    runner.run(
        { command = "dependency:sources" },
        maven_importer.Maven_Info_Pom_File[tostring(entry.info)],
        console.console_reset,
        console.console_append
    )
end

function Maven_Main_Window.download_documentation()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    runner.run(
        { command = "dependency:resolve -Dclassifier=javadoc" },
        maven_importer.Maven_Info_Pom_File[tostring(entry.info)],
        console.console_reset,
        console.console_append
    )
end

function Maven_Main_Window.download_sources_and_documentation()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    runner.run(
        { command = "dependency:sources dependency:resolve -Dclassifier=javadoc" },
        maven_importer.Maven_Info_Pom_File[tostring(entry.info)],
        console.console_reset,
        console.console_append
    )
end

function Maven_Main_Window.toggle_hide()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    if entry.hide then
        entry.hide = nil

        local ignore = {}

        for _, v in ipairs(config.ignore_files) do
            if v ~= maven_importer.Maven_Info_Pom_File[tostring(entry.info)] then
                table.insert(ignore, v)
            end

            config.ignore_files = ignore
        end
    else
        entry.hide = true

        table.insert(config.ignore_files, maven_importer.Maven_Info_Pom_File[tostring(entry.info)])
    end

    update_main_buffer()
end

function Maven_Main_Window.show_all()
    show_all = not show_all

    update_main_buffer()
end

return Maven_Main_Window
