---@class LineRoot
---@field first integer
---@field last integer
---@field item TreeEntry

---@class Highlight
---@field highlight string
---@field lineNum integer
---@field colBegin integer
---@field colEnd integer

---@class agPair
---@field a string
---@field g string

---@class TextObjNew
---@field text string
---@field hl string

---@alias TreeEntryType "project"|"lifecycle"|"plugin"|"dependency"|"file"|"container"|"command"|"error"
---@alias TreeEntryChildMap "projects"|"dependencies"|"plugins"|"files"

---@class TreeEntryChild
---@field map string
---@field key string

---@class TreeEntryNew
---@field showAlways boolean
---@field expanded boolean|nil
---@field textObjs TextObjNew[]
---@field children  TreeEntryNew[]|string[]
---@field childrenKey string?
---@field callback nil|fun():boolean
---@field info MavenInfoNew|nil
---@field error integer|nil
---@field hide boolean|nil
---@field type TreeEntryType

---@class MavenMainWindow
MavenToolsMainWindow = {}

local prefix = "maven-tools."

---@type MavenConsoleWindow
local console = require("maven-tools.ui.console")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type MavenImporter
local mavenImporter = require(prefix .. "maven.importer")

---@type MavenImporterNew
local mavenImporterNew = require(prefix .. "maven.importer_new")

---@type MavenRunner
local runner = require(prefix .. "maven.runner")

---@type integer|nil
local mavenWin = nil

---@type integer|nil
local mavenBuf = nil

---@type table<integer,fun(entry:TreeEntry):boolean>
local lineCallback = {}

---@class JavaFileTracker
---@field entries EntryInfo[]
---@field line integer

---@type table<string, JavaFileTracker>
local javaFilesMap = {}

---@type table<integer,integer?>
local lineRange = {}

---@type LineRoot[]
local lineRoots = {}

---@type integer[]
local autocmds = {}

---@type string
local filter = config.defaultFilter

---@type boolean
local showAll = false

---@type uv.uv_timer_t|nil
local projectFilesUpdateTimer = nil

---@type integer
local requestRows = 25

local entriesMap = {
    ---@type table<string, TreeEntryNew>
    projects = {},

    ---@type table<string, TreeEntryNew>
    dependencies = {},

    ---@type table<string, TreeEntryNew>
    plugins = {},

    ---@type table<string, TreeEntryNew>
    files = {},
}

---@type table<"0"|"1"|"2"|"3",fun(entry:TreeEntry):fun():boolean>
local entryCallbackMap = {
    ---@param item TreeEntry
    ---@return function
    ["0"] = function(item)
        return function()
            item.expanded = not item.expanded

            return true
        end
    end,
    ["1"] = function(item)
        ---@param entry TreeEntry
        return function(entry)
            runner.run(
                item,
                mavenImporter.mavenInfoPomFile[tostring(entry.info)],
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
    ["3"] = function(item)
        return function()
            local file = item.file

            --TODO: vvvv move to a function in utils vvvv
            if file ~= nil then
                local file_buf = utils.get_file_buffer(file)

                local editor_win = utils.get_editor_window()

                if editor_win ~= nil then
                    if file_buf == nil then
                        vim.api.nvim_win_call(editor_win, function()
                            vim.api.nvim_command("edit " .. file)
                        end)
                    else
                        vim.api.nvim_win_set_buf(editor_win, file_buf)
                    end
                end
            end

            return false
        end
    end,
}

---@param win integer
local function set_main_window_options(win)
    vim.api.nvim_set_option_value("number", false, {
        win = win,
    })

    vim.api.nvim_set_option_value("rnu", false, {
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
        width = 50,
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

local key_action_map = {
    ["toggle_item"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".toggle_item()<CR>",
    ["close_main_window"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".close_win()<CR>",
    ["project_filter"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".filter()<CR>",
    ["run_command"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".run()<CR>",
    ["add_dependency"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".add_dependency()<CR>",
    ["download_sources"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_sources()<CR>",
    ["download_documentation"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_documentation()<CR>",
    ["download_sources_and_documentation"] = "<Cmd>lua require('"
        .. prefix
        .. "ui.main')"
        .. ".download_sources_and_documentation()<CR>",
    ["hide_item"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".toggle_hide()<CR>",
    ["show_all_items"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_all()<CR>",
    ["refresh_prject"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".refresh_entry()<CR>",
    ["effective_pom"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_effective_pom()<CR>",
    ["open_pom"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".open_pom_file()<CR>",
    ["show_error"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_error()<CR>",
    ["refresh_files"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".refresh_files()<CR>",
}

MavenToolsMainWindow.keymap = {
    ["toggle_item"] = { "<CR>", "<2-Leftmouse>" },
    ["close_main_window"] = { "q" },
    ["project_filter"] = { "<C-f>" },
    ["run_command"] = { "<C-r>" },
    ["add_dependency"] = { "a" },
    ["download_sources"] = { "ds" },
    ["download_documentation"] = { "dd" },
    ["download_sources_and_documentation"] = { "da" },
    ["hide_item"] = { "h" },
    ["show_all_items"] = { "H" },
    ["refresh_prject"] = { "r" },
    ["effective_pom"] = { "ep" },
    ["open_pom"] = { "o" },
    ["show_error"] = { "e" },
    ["refresh_files"] = { "R" },
}

---@param buf integer
local function set_main_buffer_keymaps(buf)
    for key, mappings in pairs(MavenToolsMainWindow.keymap) do
        for _, mapping in ipairs(mappings) do
            vim.api.nvim_buf_set_keymap(buf, "n", mapping, key_action_map[key], {
                noremap = true,
                silent = true,
            })
        end
    end
end

---@param buf integer
---@param highlights Highlight[]
local function set_main_buffer_highlights(buf, highlights)
    for _, highlight in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(
            buf,
            -1,
            highlight.highlight,
            highlight.lineNum,
            highlight.colBegin,
            highlight.colEnd
        )
    end
end

---@param item TreeEntry
---@return fun():boolean
local make_entry_callback = function(item)
    return entryCallbackMap[item.callback](item)
end

---@param lines Array
---@param highlights Highlight[]
local function create_header(lines, highlights)
    local header = " " .. "Maven"

    table.insert(highlights, {
        highlight = "@label",
        lineNum = lines:size(),
        colBegin = 0,
        colEnd = #header,
    })

    if not mavenImporterNew.idle() then
        local progress = " ("
            .. mavenImporterNew.status
            .. " "
            .. tostring(mavenImporterNew.progress()):gsub("%.%d+", "")
            .. "%)"

        table.insert(highlights, {
            highlight = "@comment",
            lineNum = lines:size(),
            colBegin = #header,
            colEnd = #header + #progress,
        })

        header = header .. progress
    end

    lines:append(header)

    for i = 1, lines:size(), 1 do
        lineRange[i] = nil
    end

    table.insert(lineCallback, function()
        return false
    end)
end

---@param lines Array
---@param highlights Highlight[]
---@param filterEnabled boolean
local function create_footer(lines, highlights, filterEnabled)
    local line

    if filterEnabled then
        line = "(No Match Found)"
    else
        line = "(No POM Files found)"
    end

    table.insert(highlights, {
        highlight = "@comment",
        lineNum = lines:size(),
        colBegin = 0,
        colEnd = #line,
    })

    lines:append(line)

    lineRange[lines:size()] = 0

    table.insert(lineCallback, function()
        return false
    end)
end

---@param item TreeEntry
---@return boolean
local function filter_match(item)
    local info = tostring(item.info)

    if info:len() > 2 then
        if info:match(filter) ~= nil then
            return true
        end
    end

    for _, textObj in ipairs(item.textObjs) do
        if textObj.text:len() > 2 then
            if textObj.text:match(filter) ~= nil then
                return true
            end
        end
    end

    return false
end

---@param children TreeEntry[]
---@param tab string
---@param lines Array
---@param highlights Highlight[]
local function append_children(children, tab, lines, highlights)
    local currentTab = tab

    for _, child in pairs(children) do
        if child.children[1] ~= nil or child.showAlways then
            local line = currentTab

            if child.children[1] ~= nil then
                if child.expanded then
                    line = line .. " "
                else
                    line = line .. " "
                end

                table.insert(highlights, {
                    highlight = "@SignColomn",
                    lineNum = lines:size(),
                    colBegin = 0,
                    colEnd = #line,
                })
            else
                line = line .. "  "
            end

            for i, textObj in ipairs(child.textObjs) do
                line = line .. textObj.text

                if i == 1 then
                    lineRange[lines:size() + 1] = #line
                end

                table.insert(highlights, {
                    highlight = textObj.hl,
                    lineNum = lines:size(),
                    colBegin = #line - #textObj.text,
                    colEnd = #line,
                })
            end

            lines:append(line)

            table.insert(lineCallback, make_entry_callback(child))

            if child.children[1] ~= nil and child.expanded then
                append_children(child.children, currentTab .. config.tab, lines, highlights)
            end
        end
    end
end

---@param modules TreeEntry
---@param tab string
---@param lines Array
---@param highlights Highlight[]
---@param filterEnabled boolean
---@param subModule boolean
---@return boolean
local function append_modules(modules, tab, lines, highlights, filterEnabled, subModule)
    if modules == nil then
        return false
    end

    for _, module in pairs(modules.children) do
        local startLine = lines:size() + 1

        local showModule = ((subModule or not filterEnabled) and (module.hide == nil or showAll))
            or (filterEnabled and filter_match(module))

        if showModule then
            append_children(
                { module },
                (filterEnabled and not subModule) and tab or tab .. config.tab,
                lines,
                highlights
            )
        end

        if module.expanded or filterEnabled then
            append_modules(
                module.modules,
                filterEnabled and tab or tab .. config.tab,
                lines,
                highlights,
                filterEnabled,
                showModule and module.expanded == true
            )
        end

        table.insert(lineRoots, { first = startLine, last = lines:size(), item = module })
    end

    return true
end

---@return Array
---@return Highlight[]
local function generate_main_buffer_lines()
    local lines = utils.Array()

    ---@type Highlight[]
    local highlights = {}

    local filterEnabled = filter:len() > 0

    create_header(lines, highlights)

    for _, file in ipairs(mavenImporter.pomFiles) do
        local item = nil

        if
            mavenImporter.pomFileMavenInfo[file] ~= nil
            and mavenImporter.pomFileMavenInfo[file].info ~= nil
            and mavenImporter.mavenEntries[tostring(mavenImporter.pomFileMavenInfo[file].info)] ~= nil
        then
            item = mavenImporter.mavenEntries[tostring(mavenImporter.pomFileMavenInfo[file].info)]
        elseif mavenImporter.mavenEntries[file] ~= nil then
            item = mavenImporter.mavenEntries[file]
        end

        if item ~= nil then
            local startLine = lines:size()

            ---@cast item TreeEntry
            if item.module == 0 then
                local matchedItem = (item.hide == nil or showAll)

                if filterEnabled then
                    matchedItem = filter_match(item)
                end

                if matchedItem then
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
                        lineNum = lines:size(),
                        colBegin = 0,
                        colEnd = #line,
                    })

                    for i, textObj in ipairs(item.textObjs) do
                        line = line .. textObj.text

                        if i == 1 then
                            lineRange[lines:size() + 1] = #line
                        end

                        table.insert(highlights, {
                            highlight = textObj.hl,
                            lineNum = lines:size(),
                            colBegin = #line - #textObj.text,
                            colEnd = #line,
                        })
                    end

                    lines:append(line)

                    table.insert(lineCallback, make_entry_callback(item))
                end

                if item.expanded and matchedItem then
                    append_children(item.children, config.tab, lines, highlights)
                    append_modules(item.modules, "", lines, highlights, filterEnabled, true)
                elseif filterEnabled then
                    append_modules(item.modules, "", lines, highlights, filterEnabled, false)
                end

                table.insert(lineRoots, { first = startLine, last = lines:size(), item = item })
            end
        end
    end

    if lines:size() < 2 then
        create_footer(lines, highlights, filterEnabled)
    end

    return lines, highlights
end

---@class EntryInfo
---@field expanded boolean

local entriesInfo = {
    ---@type table<string, EntryInfo>
    projects = {},

    ---@type table<string, EntryInfo>
    plugins = {},

    container = {
        ---@type table<string, EntryInfo>
        lifecycle = {},

        ---@type table<string, EntryInfo>
        plugins = {},

        ---@type table<string, EntryInfo>
        dependencies = {},

        ---@type table<string, EntryInfo>
        files = {},

        ---@type table<string, table<"files"|"tests", table<string, EntryInfo>>>
        folders = {},
    },
}

---@type table<integer, fun(callback:fun(entryType:TreeEntryType, entryInfo:EntryInfo?, projectInfo:ProjectInfo|nil, args:table))>
local lineCallbackNew = {}

---@param lineNum integer
---@param line string
---@param str string
---@param hl string
---@param highlights Highlight[]
---@return string
local function line_cat_highlight(lineNum, line, str, hl, highlights)
    local highlight = { highlight = hl, lineNum = lineNum }
    highlight.colBegin = #line
    line = line .. str
    highlight.colEnd = #line

    table.insert(highlights, highlight)

    return line
end

---@param currentTab string
---@param mavenInfoStr string
---@param projectInfo ProjectInfo
---@param lines Array
---@param highlights Highlight[]
local function generate_project_lifecycle_lines(currentTab, mavenInfoStr, projectInfo, lines, highlights)
    if config.lifecycleCommands[1] == nil or config.showLifecycle == false then
        return
    end

    if entriesInfo.container.lifecycle[mavenInfoStr] == nil then
        entriesInfo.container.lifecycle[mavenInfoStr] = { expanded = false }
    end

    local line = currentTab

    line = line_cat_highlight(
        lines:size(),
        line,
        entriesInfo.container.lifecycle[mavenInfoStr].expanded and " " or " ",
        config.signHighlight,
        highlights
    )

    line = line_cat_highlight(lines:size(), line, "󱂀 ", config.containerIconHighlight, highlights)

    lineRange[lines:size() + 1] = #line

    line = line_cat_highlight(lines:size(), line, "Lifecycle", config.containerTextHighlight, highlights)

    lines:append(line)

    lineCallbackNew[lines:size()] = function(callback)
        return callback("container", entriesInfo.container.lifecycle[mavenInfoStr], projectInfo, {})
    end

    if entriesInfo.container.lifecycle[mavenInfoStr].expanded then
        currentTab = currentTab .. config.tab

        for _, lifecycle in ipairs(config.lifecycleCommands) do
            line = currentTab

            line = line_cat_highlight(lines:size(), line, " ", config.lifecycleIconHighlight, highlights)

            lineRange[lines:size() + 1] = #line

            line = line_cat_highlight(lines:size(), line, lifecycle, config.lifecycleTextHighlight, highlights)

            lines:append(line)

            lineCallbackNew[lines:size()] = function(callback)
                return callback(
                    "command",
                    entriesInfo.container.lifecycle[mavenInfoStr],
                    projectInfo,
                    { command = lifecycle }
                )
            end
        end
    end
end

---@param currentTab string
---@param mavenInfoStr string
---@param projectInfo ProjectInfo
---@param lines Array
---@param highlights Highlight[]
local function generate_project_dependencies_lines(currentTab, mavenInfoStr, projectInfo, lines, highlights)
    if projectInfo.dependencies[1] == nil or config.showDependencies == false then
        return
    end

    if entriesInfo.container.dependencies[mavenInfoStr] == nil then
        entriesInfo.container.dependencies[mavenInfoStr] = { expanded = false }
    end

    local line = currentTab

    line = line_cat_highlight(
        lines:size(),
        line,
        entriesInfo.container.dependencies[mavenInfoStr].expanded and " " or " ",
        config.signHighlight,
        highlights
    )

    line = line_cat_highlight(lines:size(), line, " ", config.containerIconHighlight, highlights)

    lineRange[lines:size() + 1] = #line

    line = line_cat_highlight(lines:size(), line, "Dependencies", config.containerTextHighlight, highlights)

    lines:append(line)

    lineCallbackNew[lines:size()] = function(callback)
        return callback("container", entriesInfo.container.dependencies[mavenInfoStr], projectInfo, {})
    end

    if entriesInfo.container.dependencies[mavenInfoStr].expanded then
        currentTab = currentTab .. config.tab

        for _, dependency in ipairs(projectInfo.dependencies) do
            line = currentTab

            line = line_cat_highlight(lines:size(), line, " ", config.dependencyIconHighlight, highlights)

            lineRange[lines:size() + 1] = #line

            if dependency.groupId ~= nil then
                line = line_cat_highlight(
                    lines:size(),
                    line,
                    dependency.groupId,
                    config.dependencyTextHighlight,
                    highlights
                )
            end

            if dependency.artifactId ~= nil then
                line = line_cat_highlight(
                    lines:size(),
                    line,
                    ":" .. dependency.artifactId,
                    config.dependencyTextHighlight,
                    highlights
                )
            end

            if dependency.version ~= nil then
                line = line_cat_highlight(
                    lines:size(),
                    line,
                    ":" .. dependency.version,
                    config.dependencyTextHighlight,
                    highlights
                )
            end

            if dependency.scope ~= nil and dependency.scope ~= "compile" then
                line = line_cat_highlight(
                    lines:size(),
                    line,
                    " (" .. dependency.scope .. ")",
                    config.commentHighlight,
                    highlights
                )
            end

            lines:append(line)

            lineCallbackNew[lines:size()] = function(callback)
                return callback("dependency", nil, projectInfo, {})
            end
        end
    end
end

---@param currentTab string
---@param mavenInfoStr string
---@param projectInfo ProjectInfo
---@param lines Array
---@param highlights Highlight[]
local function generate_project_plugins_lines(currentTab, mavenInfoStr, projectInfo, lines, highlights)
    if projectInfo.plugins[1] == nil or config.showPlugins == false then
        return
    end

    if entriesInfo.container.plugins[mavenInfoStr] == nil then
        entriesInfo.container.plugins[mavenInfoStr] = { expanded = false }
    end

    local line = currentTab

    line = line_cat_highlight(
        lines:size(),
        line,
        entriesInfo.container.plugins[mavenInfoStr].expanded and " " or " ",
        config.signHighlight,
        highlights
    )

    line = line_cat_highlight(lines:size(), line, "󱧽 ", config.containerIconHighlight, highlights)

    lineRange[lines:size() + 1] = #line

    line = line_cat_highlight(lines:size(), line, "Plugins", config.containerTextHighlight, highlights)

    lines:append(line)

    lineCallbackNew[lines:size()] = function(callback)
        return callback("container", entriesInfo.container.plugins[mavenInfoStr], projectInfo, {})
    end

    if entriesInfo.container.plugins[mavenInfoStr].expanded then
        currentTab = currentTab .. config.tab

        for _, plugin in ipairs(projectInfo.plugins) do
            local pluginInfoStr = mavenImporterNew.info_to_str(plugin)

            if entriesInfo.plugins[pluginInfoStr] == nil then
                entriesInfo.plugins[pluginInfoStr] = { expanded = false }
            end

            if mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr] ~= nil then
                line = currentTab

                local sign

                if mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr].commands[1] ~= nil then
                    if entriesInfo.plugins[pluginInfoStr].expanded then
                        sign = " "
                    else
                        sign = " "
                    end
                else
                    sign = "  "
                end

                line = line_cat_highlight(lines:size(), line, sign, config.signHighlight, highlights)

                line = line_cat_highlight(lines:size(), line, " ", config.pluginIconHighlight, highlights)

                lineRange[lines:size() + 1] = #line

                line = line_cat_highlight(
                    lines:size(),
                    line,
                    mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr].goal,
                    config.pluginTextHighlight,
                    highlights
                )

                lines:append(line)

                lineCallbackNew[lines:size()] = function(callback)
                    return callback(
                        "plugin",
                        entriesInfo.plugins[pluginInfoStr],
                        projectInfo,
                        { infoStr = pluginInfoStr }
                    )
                end

                if entriesInfo.plugins[pluginInfoStr].expanded then
                    currentTab = currentTab .. config.tab

                    for _, pluginCommand in ipairs(mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr].commands) do
                        line = currentTab

                        line = line_cat_highlight(lines:size(), line, " ", config.pluginIconHighlight, highlights)

                        lineRange[lines:size() + 1] = #line

                        line = line_cat_highlight(
                            lines:size(),
                            line,
                            pluginCommand,
                            config.pluginTextHighlight,
                            highlights
                        )

                        lines:append(line)

                        lineCallbackNew[lines:size()] = function(callback)
                            return callback("command", nil, projectInfo, {
                                command = mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr].goal
                                    .. ":"
                                    .. pluginCommand,
                                infoStr = pluginInfoStr,
                            })
                        end
                    end

                    currentTab = currentTab:gsub(config.tab, "", 1)
                end
            end
        end
    end
end

---@param file ProjectFile
---@return "class"|"interface"|"@interface"|"enum"|nil
local function get_java_file_type(file)
    if file == nil then
        return
    end

    if mavenImporterNew.fileProperties[file.path] ~= nil then
        return mavenImporterNew.fileProperties[file.path].type
    end
end

---@param file string
---@return boolean
local function is_java_file_test(file) end

---@param file ProjectFile
---@return boolean
local function is_java_file_runnable(file)
    if file == nil then
        return false
    end

    if mavenImporterNew.fileProperties[file.path] ~= nil then
        if
            mavenImporterNew.fileProperties[file.path].main == true
            or (
                mavenImporterNew.fileProperties[file.path].importsJunit == true
                and mavenImporterNew.fileProperties[file.path].test == true
            )
        then
            return true
        end
    end

    return false
end

---@param file string
---@param entry EntryInfo
local function append_java_file_to_map(file, entry)
    table.insert(javaFilesMap[file].entries, entry)
end

---@param currentTab string
---@param mavenInfoStr string
---@param projectInfo ProjectInfo
---@param lines Array
---@param highlights Highlight[]
---@param parents string[]
---@param parentVisible boolean
local function generate_project_files_lines(
    currentTab,
    mavenInfoStr,
    projectInfo,
    lines,
    highlights,
    parents,
    parentVisible
)
    if config.showFiles == false or (next(projectInfo.files) == nil and next(projectInfo.testFiles) == nil) then
        return
    end

    if entriesInfo.container.files[mavenInfoStr] == nil then
        entriesInfo.container.files[mavenInfoStr] = { expanded = false }
    end

    if entriesInfo.container.folders[mavenInfoStr] == nil then
        entriesInfo.container.folders[mavenInfoStr] = { files = {}, tests = {} }
    end

    local line = currentTab

    if parentVisible then
        local sign
        if entriesInfo.container.files[mavenInfoStr].expanded then
            sign = " "
        else
            sign = " "
        end

        line = line_cat_highlight(lines:size(), line, sign, config.signHighlight, highlights)

        line = line_cat_highlight(lines:size(), line, " ", config.containerIconHighlight, highlights)

        lineRange[lines:size() + 1] = #line

        line = line_cat_highlight(lines:size(), line, "Files", config.containerTextHighlight, highlights)

        lines:append(line)

        lineCallbackNew[lines:size()] = function(callback)
            return callback("container", entriesInfo.container.files[mavenInfoStr], projectInfo, {})
        end
    end

    if entriesInfo.container.files[mavenInfoStr].expanded and parentVisible then
        currentTab = currentTab .. config.tab

        for folder, files in pairs(projectInfo.files) do
            if files[1] ~= nil then
                if entriesInfo.container.folders[mavenInfoStr].files[folder] == nil then
                    entriesInfo.container.folders[mavenInfoStr].files[folder] = { expanded = false }
                end

                local sign
                line = currentTab

                if entriesInfo.container.folders[mavenInfoStr].files[folder].expanded then
                    sign = " "
                else
                    sign = " "
                end

                line = line_cat_highlight(lines:size(), line, sign, config.packageIconHighlight, highlights)

                lineRange[lines:size() + 1] = #line

                line = line_cat_highlight(lines:size(), line, folder, config.packageTextHighlight, highlights)

                lines:append(line)

                lineCallbackNew[lines:size()] = function(callback)
                    return callback(
                        "container",
                        entriesInfo.container.folders[mavenInfoStr].files[folder],
                        projectInfo,
                        {}
                    )
                end

                if entriesInfo.container.folders[mavenInfoStr].files[folder].expanded and parentVisible then
                    currentTab = currentTab .. config.tab

                    for _, file in ipairs(files) do
                        line = currentTab

                        local fileType = get_java_file_type(file)

                        if fileType == nil then
                            line = line_cat_highlight(lines:size(), line, " ", config.fileIconHighlight, highlights)
                        elseif fileType == "class" then
                            line = line_cat_highlight(lines:size(), line, "󰯳 ", config.fileIconHighlight, highlights)
                        elseif fileType == "interface" then
                            line = line_cat_highlight(lines:size(), line, "󰰅 ", config.fileIconHighlight, highlights)
                        elseif fileType == "@interface" then
                            line = line_cat_highlight(lines:size(), line, "󰁥 ", config.fileIconHighlight, highlights)
                        elseif fileType == "enum" then
                            line = line_cat_highlight(lines:size(), line, "󰯹 ", config.fileIconHighlight, highlights)
                        end

                        if is_java_file_runnable(file) then
                            line = line_cat_highlight(
                                lines:size(),
                                line,
                                " ",
                                config.testPackageIconHighlight,
                                highlights
                            )
                        end

                        lineRange[lines:size() + 1] = #line
                        line =
                            line_cat_highlight(lines:size(), line, file.filename, config.fileTextHighlight, highlights)

                        lines:append(line)

                        lineCallbackNew[lines:size()] = function(callback)
                            return callback("file", nil, projectInfo, { path = file.path })
                        end

                        javaFilesMap[file.path] = { line = lines:size(), entries = {} }
                        append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].files[folder])
                        append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
                        append_java_file_to_map(file.path, entriesInfo.projects[mavenInfoStr])

                        for _, parent in ipairs(parents) do
                            append_java_file_to_map(file.path, entriesInfo.projects[parent])
                        end
                    end

                    currentTab = currentTab:gsub(config.tab, "", 1)
                end
            end
        end

        for folder, files in pairs(projectInfo.testFiles) do
            if files[1] ~= nil then
                if entriesInfo.container.folders[mavenInfoStr].tests[folder] == nil then
                    entriesInfo.container.folders[mavenInfoStr].tests[folder] = { expanded = false }
                end

                local sign
                line = currentTab

                if entriesInfo.container.folders[mavenInfoStr].tests[folder].expanded then
                    sign = " "
                else
                    sign = " "
                end

                line = line_cat_highlight(lines:size(), line, sign, config.testPackageIconHighlight, highlights)

                lineRange[lines:size() + 1] = #line

                line = line_cat_highlight(lines:size(), line, folder, config.testPackageTextHighlight, highlights)
                line = line_cat_highlight(lines:size(), line, " [test]", config.commentHighlight, highlights)

                lines:append(line)

                lineCallbackNew[lines:size()] = function(callback)
                    return callback(
                        "container",
                        entriesInfo.container.folders[mavenInfoStr].tests[folder],
                        projectInfo,
                        {}
                    )
                end

                if entriesInfo.container.folders[mavenInfoStr].tests[folder].expanded then
                    currentTab = currentTab .. config.tab

                    for _, file in ipairs(files) do
                        line = currentTab

                        local fileType = get_java_file_type(file)

                        if fileType == nil then
                            line = line_cat_highlight(lines:size(), line, " ", config.fileIconHighlight, highlights)
                        elseif fileType == "class" then
                            line = line_cat_highlight(lines:size(), line, "󰯳 ", config.fileIconHighlight, highlights)
                        elseif fileType == "interface" then
                            line = line_cat_highlight(lines:size(), line, "󰰅 ", config.fileIconHighlight, highlights)
                        elseif fileType == "@interface" then
                            line = line_cat_highlight(lines:size(), line, "󰁥 ", config.fileIconHighlight, highlights)
                        elseif fileType == "enum" then
                            line = line_cat_highlight(lines:size(), line, "󰯹 ", config.fileIconHighlight, highlights)
                        end

                        if is_java_file_runnable(file) then
                            line = line_cat_highlight(
                                lines:size(),
                                line,
                                " ",
                                config.testPackageIconHighlight,
                                highlights
                            )
                        end

                        lineRange[lines:size() + 1] = #line
                        line =
                            line_cat_highlight(lines:size(), line, file.filename, config.fileTextHighlight, highlights)

                        lines:append(line)

                        lineCallbackNew[lines:size()] = function(callback)
                            return callback("file", nil, projectInfo, { path = file.path })
                        end

                        javaFilesMap[file.path] = { line = lines:size(), entries = {} }
                        append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].tests[folder])
                        append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
                        append_java_file_to_map(file.path, entriesInfo.projects[mavenInfoStr])

                        for _, parent in ipairs(parents) do
                            append_java_file_to_map(file.path, entriesInfo.projects[parent])
                        end
                    end

                    currentTab = currentTab:gsub(config.tab, "", 1)
                end
            end
        end
    else
        for folder, files in pairs(projectInfo.files) do
            if files[1] ~= nil then
                if entriesInfo.container.folders[mavenInfoStr].files[folder] == nil then
                    entriesInfo.container.folders[mavenInfoStr].files[folder] = { expanded = false }
                end

                for _, file in ipairs(files) do
                    javaFilesMap[file.path] = { line = lines:size(), entries = {} }
                    append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].files[folder])
                    append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
                    append_java_file_to_map(file.path, entriesInfo.projects[mavenInfoStr])

                    for _, parent in ipairs(parents) do
                        append_java_file_to_map(file.path, entriesInfo.projects[parent])
                    end
                end
            end
        end

        for folder, files in pairs(projectInfo.testFiles) do
            if files[1] ~= nil then
                if entriesInfo.container.folders[mavenInfoStr].tests[folder] == nil then
                    entriesInfo.container.folders[mavenInfoStr].tests[folder] = { expanded = false }
                end

                for _, file in ipairs(files) do
                    javaFilesMap[file.path] = { line = lines:size(), entries = {} }
                    append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].tests[folder])
                    append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
                    append_java_file_to_map(file.path, entriesInfo.projects[mavenInfoStr])

                    for _, parent in ipairs(parents) do
                        append_java_file_to_map(file.path, entriesInfo.projects[parent])
                    end
                end
            end
        end
    end
end

---@param currentTab string
---@param mavenInfoStr string
---@param projectInfo ProjectInfo
---@param lines Array
---@param highlights Highlight[]
---@param parents string[]
---@param parentVisible boolean
local function generate_project_lines(currentTab, mavenInfoStr, projectInfo, lines, highlights, parents, parentVisible)
    if entriesInfo.projects[mavenInfoStr] == nil then
        entriesInfo.projects[mavenInfoStr] = { expanded = false }
    end

    if parentVisible then
        local line = currentTab

        line = line_cat_highlight(
            lines:size(),
            line,
            entriesInfo.projects[mavenInfoStr].expanded and " " or " ",
            config.signHighlight,
            highlights
        )

        line = line_cat_highlight(lines:size(), line, " ", config.projectIconHighlight, highlights)

        lineRange[lines:size() + 1] = #line

        line = line_cat_highlight(lines:size(), line, projectInfo.name, config.projectTextHighlight, highlights)

        lines:append(line)

        lineCallbackNew[lines:size()] = function(callback)
            return callback("project", entriesInfo.projects[mavenInfoStr], projectInfo, {})
        end
    end

    if entriesInfo.projects[mavenInfoStr].expanded and parentVisible then
        generate_project_lifecycle_lines(currentTab .. config.tab, mavenInfoStr, projectInfo, lines, highlights)
        generate_project_dependencies_lines(currentTab .. config.tab, mavenInfoStr, projectInfo, lines, highlights)
        generate_project_plugins_lines(currentTab .. config.tab, mavenInfoStr, projectInfo, lines, highlights)
        generate_project_files_lines(
            currentTab .. config.tab,
            mavenInfoStr,
            projectInfo,
            lines,
            highlights,
            parents,
            true
        )

        -- table.insert(parents, mavenInfoStr)

        for _, modulePomFile in ipairs(projectInfo.modules) do
            local currentParents = utils.deepcopy(parents)
            table.insert(currentParents, mavenInfoStr)
            if mavenImporterNew.pomFileToMavenInfoMap[modulePomFile] ~= nil then
                local moduleInfoStr =
                    mavenImporterNew.info_to_str(mavenImporterNew.pomFileToMavenInfoMap[modulePomFile].info)

                if mavenImporterNew.mavenInfoToProjectInfoMap[moduleInfoStr] ~= nil then
                    generate_project_lines(
                        currentTab .. config.tab,
                        moduleInfoStr,
                        mavenImporterNew.mavenInfoToProjectInfoMap[moduleInfoStr],
                        lines,
                        highlights,
                        currentParents,
                        true
                    )
                end
            end
        end
    else
        generate_project_files_lines(
            currentTab .. config.tab,
            mavenInfoStr,
            projectInfo,
            lines,
            highlights,
            parents,
            false
        )

        -- table.insert(parents, mavenInfoStr)

        for _, modulePomFile in ipairs(projectInfo.modules) do
            local currentParents = utils.deepcopy(parents)
            table.insert(currentParents, mavenInfoStr)

            if mavenImporterNew.pomFileToMavenInfoMap[modulePomFile] ~= nil then
                local moduleInfoStr =
                    mavenImporterNew.info_to_str(mavenImporterNew.pomFileToMavenInfoMap[modulePomFile].info)

                if mavenImporterNew.mavenInfoToProjectInfoMap[moduleInfoStr] ~= nil then
                    generate_project_lines(
                        currentTab .. config.tab,
                        moduleInfoStr,
                        mavenImporterNew.mavenInfoToProjectInfoMap[moduleInfoStr],
                        lines,
                        highlights,
                        currentParents,
                        false
                    )
                end
            end
        end
    end
end

---@return Array
---@return Highlight[]
local function generate_main_buffer_lines_new()
    local lines = utils.Array()

    ---@type Highlight[]
    local highlights = {}

    local filterEnabled = filter:len() > 0

    create_header(lines, highlights)

    for mavenInfoStr, projectInfo in pairs(mavenImporterNew.mavenInfoToProjectInfoMap) do
        if mavenImporterNew.pomFileIsModuleSet[projectInfo.pomFile] == nil then
            generate_project_lines("", mavenInfoStr, projectInfo, lines, highlights, {}, true)
        end
    end

    for pomFile, error in pairs(mavenImporterNew.pomFileToErrorMap) do
        if error ~= nil then
            local line = ""

            line = line_cat_highlight(lines:size(), line, " ", config.projectErrorIconHighlight, highlights)
            line = line_cat_highlight(lines:size(), line, "error", config.projectErrorTextHighlight, highlights)
            lineRange[lines:size() + 1] = #line
            line = line_cat_highlight(lines:size(), line, " ", config.projectTextHighlight, highlights)
            line = line_cat_highlight(
                lines:size(),
                line,
                "[" .. pomFile:gsub(utils.Path(config.cwd).str .. "/", "") .. "]",
                config.projectTextHighlight,
                highlights
            )

            lines:append(line)

            lineCallbackNew[lines:size()] = function(callback)
                return callback("error", nil, nil, { file = pomFile, error = error })
            end
        end
    end

    if lines:size() < 2 then
        create_footer(lines, highlights, filterEnabled)
    end

    return lines, highlights
end

local function create_main_buffer()
    lineCallback = {}
    lineRange = {}
    lineRoots = {}

    local buf = vim.api.nvim_create_buf(false, true)

    -- local lines, highlights = generate_main_buffer_lines()
    local lines, highlights = generate_main_buffer_lines_new()

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines:values())

    set_main_buffer_options(buf)
    set_main_buffer_keymaps(buf)
    set_main_buffer_highlights(buf, highlights)

    return buf
end

local function update_main_buffer(updateCursor)
    mavenBuf = create_main_buffer()
    local line = vim.fn.line(".")
    local col = vim.fn.col(".")

    if mavenWin ~= nil then
        vim.api.nvim_win_set_buf(mavenWin, mavenBuf)
    end

    if mavenWin ~= nil and updateCursor == nil then
        if vim.api.nvim_get_current_win() == mavenWin then
            pcall(function()
                vim.api.nvim_win_set_cursor(mavenWin, { line, col - 1 })
            end)
        end
    end
end

local function main_window_close_handler()
    if projectFilesUpdateTimer ~= nil then
        projectFilesUpdateTimer:stop()
        projectFilesUpdateTimer:close()
    end

    mavenBuf = nil
    mavenWin = nil

    for _, autocmd in ipairs(autocmds) do
        vim.api.nvim_del_autocmd(autocmd)
    end

    autocmds = {}
end

local restoreEntries = {}
local restoreEntiresCallback = nil

local function initialize_autocmds()
    table.insert(
        autocmds,
        vim.api.nvim_create_autocmd("CursorMoved", {
            callback = function()
                if mavenWin ~= nil and mavenBuf ~= nil then
                    if vim.api.nvim_get_current_win() == mavenWin then
                        local line = vim.fn.line(".")
                        local col = vim.fn.col(".")

                        if lineRange[line] == nil then
                            if vim.api.nvim_buf_line_count(mavenBuf) > line and lineRange[line + 1] ~= nil then
                                vim.api.nvim_win_set_cursor(mavenWin, { line + 1, lineRange[line + 1] })
                            end
                        else
                            if lineRange[line] ~= nil then
                                if col <= lineRange[line] then
                                    vim.api.nvim_win_set_cursor(mavenWin, { line, lineRange[line] })
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
                if mavenWin ~= nil and mavenBuf ~= nil then
                    local new_buf = vim.api.nvim_win_get_buf(mavenWin)

                    if new_buf ~= mavenBuf then
                        vim.schedule(function()
                            vim.api.nvim_win_set_buf(mavenWin, mavenBuf)

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
                if mavenWin ~= nil then
                    if tonumber(event.match) == mavenWin then
                        main_window_close_handler()
                    end
                end
            end,
        })
    )

    table.insert(
        autocmds,
        vim.api.nvim_create_autocmd("BufEnter", {
            callback = function()
                if mavenWin ~= nil then
                    local buf = vim.api.nvim_get_current_buf()
                    local bufName = utils.Path(vim.api.nvim_buf_get_name(buf)).str

                    if buf ~= mavenBuf and restoreEntiresCallback ~= nil then
                        restoreEntiresCallback()
                    end

                    restoreEntries = {}

                    restoreEntiresCallback = function()
                        for _, v in ipairs(restoreEntries) do
                            v.entry.expanded = v.value
                        end
                    end

                    if javaFilesMap[bufName] ~= nil then
                        for _, entry in ipairs(javaFilesMap[bufName].entries) do
                            table.insert(restoreEntries, { entry = entry, value = entry.expanded })
                            entry.expanded = true
                        end

                        update_main_buffer(1)

                        vim.api.nvim_win_set_cursor(mavenWin, { javaFilesMap[bufName].line, 1 })
                    end
                end
            end,
        })
    )

    -- if config.autoRefreshProjectFiles then
    --     projectFilesUpdateTimer = vim.uv.new_timer()
    --
    --     if projectFilesUpdateTimer ~= nil then
    --         projectFilesUpdateTimer:start(0, 10000, vim.schedule_wrap(MavenToolsMainWindow.refresh_files))
    --     end
    -- end
end

function MavenToolsMainWindow.show_main_window()
    if mavenWin == nil then
        mavenBuf = create_main_buffer()
        mavenWin = create_main_window(mavenBuf)
        initialize_autocmds()
        update_main_buffer()
    end
end

local function init()
    local cwd = config.cwd
    vim.api.nvim_set_hl(0, "MavenToolsContainerIcon", { fg = "#54c6f7" })
    vim.api.nvim_set_hl(0, "MavenToolsProjectIcon", { fg = "#548AF7" })
    vim.api.nvim_set_hl(0, "MavenToolsJavaPackageIcon", { fg = "#548AF7" })
    vim.api.nvim_set_hl(0, "MavenToolsJavaTestPackageIcon", { fg = "#57965C" })
    vim.api.nvim_set_hl(0, "MavenToolsJavaFileIcon", { fg = "#de7118" })

    if cwd ~= nil then
        vim.schedule(function()
            -- mavenImporter.process_pom_files(cwd, update_main_buffer)
            mavenImporterNew.update(cwd, update_main_buffer)
        end)
    end

    vim.api.nvim_create_user_command("MavenHideConsole", console.hide, {})
    vim.api.nvim_create_user_command("MavenShow", MavenToolsMainWindow.show_main_window, {})

    initialize_autocmds()
end

function MavenToolsMainWindow:start()
    MavenToolsMainWindow.show_main_window()

    init()
end

function MavenToolsMainWindow.toggle_item()
    local line = vim.fn.line(".")
    local col = vim.fn.col(".")

    if type(lineCallbackNew[line]) == "function" then
        lineCallbackNew[line](function(entryType, entryInfo, projectInfo, arg)
            if entryType == "command" and projectInfo ~= nil then
                runner.run(arg, projectInfo.pomFile, console.console_reset, console.console_append)
            elseif entryType == "file" then
                utils.open_file(arg.path)
            elseif entryInfo ~= nil and entryInfo.expanded ~= nil then
                entryInfo.expanded = not entryInfo.expanded

                update_main_buffer(1)
            end
        end)
    end

    if mavenWin ~= nil then
        vim.api.nvim_win_set_cursor(mavenWin, { line, col - 1 })
    end

    -- local line = vim.fn.line(".")
    -- local col = vim.fn.col(".")
    --
    -- local entry
    --
    -- for _, v in ipairs(lineRoots) do
    --     if line >= v.first and line <= v.last then
    --         entry = v.item
    --         break
    --     end
    -- end
    --
    -- if type(lineCallback[line]) == "function" then
    --     if lineCallback[line](entry) then
    --         update_main_buffer()
    --     end
    --
    --     if mavenWin ~= nil then
    --         vim.api.nvim_win_set_cursor(mavenWin, { line, col - 1 })
    --     end
    -- end
end

function MavenToolsMainWindow.close_win()
    if mavenWin ~= nil then
        vim.api.nvim_win_close(mavenWin, true)
    end
end

function MavenToolsMainWindow.filter()
    filter = vim.fn.input("Filter: " .. filter)

    update_main_buffer()
end

---@return TreeEntry|nil
local function get_current_entry()
    local line = vim.fn.line(".")

    for _, lineRoot in ipairs(lineRoots) do
        if line >= lineRoot.first and line <= lineRoot.last then
            return lineRoot.item
        end
    end
end

---@param entry TreeEntry
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

        for _, textObj in pairs(entry.textObjs) do
            text = text .. textObj.text
        end

        table.insert(items, text)
    end

    for _, child in pairs(entry.children) do
        get_entry_targets(child, targets, items)
    end

    return targets, items
end

---@param callback fun(entry:TreeEntry)
local function select_target(callback)
    local items = {}
    local entries = {}

    for info, project in pairs(mavenImporter.mavenEntries) do
        table.insert(items, project.textObjs[2].text .. "(" .. info .. ")")
        table.insert(entries, project)
    end

    vim.ui.select(items, {
        prompt = "Select target project",
    }, function(item, idx)
        if idx ~= nil then
            callback(entries[idx])
        end
    end)
    return
end

---@param entry TreeEntry|number|nil
function MavenToolsMainWindow.run(entry)
    if entry == nil then
        entry = get_current_entry()
    elseif type(entry) == "number" then
        select_target(MavenToolsMainWindow.run)
        return
    end

    if entry == nil then
        return
    end

    local targets, items = get_entry_targets(entry)

    vim.ui.select(items, {
        prompt = "Run (" .. entry.textObjs[2].text .. ")",
    }, function(item, idx)
        ---TODO:
        print(item, idx)
    end)
end

---TODO: move to utils
---@param callback fun(err:any, content:string|nil):any
---@return any
local function fetch_url(url, callback)
    local command

    if config.OS == "Windows" then
        command = {
            "powershell",
            "-NoProfile",
            "-Command",
            "Invoke-WebRequest",
            "-Uri",
            "'" .. url .. "'",
            "|",
            "Select-Object",
            "-ExpandProperty",
            "Content",
        }
    elseif vim.fn.executable("curl") == 1 then
        command = { "curl", "-fsSL", url }
    elseif vim.fn.executable("wget") == 1 then
        command = { "wget", "-qO-", url }
    else
        callback(nil, "No suitable HTTP client found (need curl, wget, or PowerShell)")
        return
    end

    vim.schedule(function()
        local response = vim.fn.system(command)

        if vim.v.shell_error ~= 0 then
            callback(nil, "Failed to fetch URL: " .. url)
        else
            callback(response, nil)
        end
    end)
end

---@param content string
---@param err any
---@return string[]|nil
---@return table<string, agPair>|nil
---@return integer|nil
---@return integer|nil
---@return integer|nil
local function parse_packages_json(content, err)
    if err then
        print("Error:", err)
    else
        local json = vim.fn.json_decode(content)

        if json == nil then
            print("Failed to parse JSON")
            return
        end

        if json.response == nil then
            print("No response found in JSON")
            return
        end

        if json.response.numFound == nil or json.response.numFound == 0 then
            -- print("No results found for:", dependency)
            return
        end

        if json.response.start == nil then
            -- print("No results found for:", dependency)
            return
        end

        if json.response.docs == nil then
            print("No artifacts found in JSON")
            return
        end

        local items = {}
        local count = 0

        ---@type table<string, agPair>
        local agPairs = {}

        for _, doc in ipairs(json.response.docs) do
            table.insert(items, doc.id)
            agPairs[doc.id] = { a = doc.a, g = doc.g }
            count = count + 1
        end

        return items, agPairs, count, json.response.numFound, json.response.start
    end
end

---@param content string
---@param err any
---@return string[]|nil
---@return integer|nil
---@return integer|nil
---@return integer|nil
local function parse_package_versions_json(content, err)
    if err then
        print("Error:", err)
    else
        local json = vim.fn.json_decode(content)

        if json == nil then
            print("Failed to parse JSON")
            return
        end

        if json.response == nil then
            print("No response found in JSON")
            return
        end

        if json.response.numFound == nil or json.response.numFound == 0 then
            -- print("No results found for:", dependency)
            return
        end

        if json.response.start == nil then
            return
        end

        if json.response.docs == nil then
            print("No artifacts found in JSON")
            return
        end

        local items = {}
        local count = 0

        for _, artifact in ipairs(json.response.docs) do
            table.insert(items, artifact.v)
            count = count + 1
        end

        return items, count, json.response.numFound, json.response.start
    end
end

---@param groupId string
---@param artifactId string
---@param callback fun(groupId:string, artifactId:string, version:string)
---@param start integer|nil
local function select_package_version(groupId, artifactId, callback, start)
    if start == nil then
        start = 0
    end

    fetch_url(
        "https://search.maven.org/solrsearch/select?q=g:%22"
            .. groupId
            .. "%22+AND+a:%22"
            .. artifactId
            .. "%22&rows="
            .. tostring(requestRows)
            .. "&core=gav&start="
            .. tostring(start)
            .. "&wt=json",
        function(content, err)
            local items, count, numFound, current = parse_package_versions_json(content, err)

            if items == nil then
                return
            end

            local pages = math.ceil(numFound / requestRows)
            local page = math.floor(current / requestRows) + 1

            if pages > 1 and page < pages then
                table.insert(items, "next (" .. tostring(page) .. "/" .. tostring(pages) .. ")")
            end

            vim.ui.select(items, {
                prompt = "Select Version (" .. groupId .. ":" .. artifactId .. ")",
            }, function(item, idx)
                if item == nil or idx == nil then
                    return
                end

                if idx <= count then
                    callback(groupId, artifactId, item)
                else
                    select_package_version(groupId, artifactId, callback, current + requestRows)
                end
            end)
        end
    )
end

---@param entry TreeEntry
---@param dependency string
---@param callback fun(groupId:string, artifactId:string, version:string)
---@param start integer|nil
local function select_package(entry, dependency, callback, start)
    if start == nil then
        start = 0
    end

    fetch_url(
        "https://search.maven.org/solrsearch/select?q="
            .. dependency
            .. "&rows="
            .. tostring(requestRows)
            .. "&start="
            .. tostring(start)
            .. "&wt=json",
        function(err, content)
            local items, agPairs, count, numFound, current = parse_packages_json(err, content)

            if items == nil or agPairs == nil then
                return
            end

            local pages = math.ceil(numFound / requestRows)
            local page = math.floor(current / requestRows) + 1

            if pages > 1 and page < pages then
                table.insert(items, "next (" .. tostring(page) .. "/" .. tostring(pages) .. ")")
            end

            vim.ui.select(items, {
                prompt = "Add Dependency (" .. entry.textObjs[2].text .. ")",
            }, function(item, idx)
                if item == nil or idx == nil then
                    return
                end

                if idx <= count then
                    select_package_version(agPairs[item].g, agPairs[item].a, callback)
                else
                    select_package(entry, dependency, callback, current + requestRows)
                end
            end)
        end
    )
end

---@param entry TreeEntry|number|nil
function MavenToolsMainWindow.add_dependency(entry)
    if entry == nil then
        entry = get_current_entry()
    elseif type(entry) == "number" then
        select_target(MavenToolsMainWindow.add_dependency)
        return
    end

    if entry == nil then
        return
    end

    local dependency = vim.fn.input("Search")

    if dependency == nil or dependency == "" then
        return
    end

    select_package(entry, dependency, function(groupId, artifactId, version)
        local pomFile = mavenImporter.mavenInfoPomFile[tostring(entry.info)]

        if pomFile == nil then
            return
        end

        local file = io.open(pomFile, "r")

        if not file then
            return
        end

        local xmlContent = file:read("*all")

        file:close()

        local newDependency = string.format(
            "    <dependency>\n        <groupId>%s</groupId>\n        <artifactId>%s</artifactId>\n        <version>%s</version>\n    </dependency>\n",
            groupId,
            artifactId,
            version
        )

        local subCount
        xmlContent, subCount = xmlContent:gsub("(</dependencies>)", newDependency .. "%1", 1)

        if subCount == 0 then
            xmlContent, subCount = xmlContent:gsub(
                "(</project>)",
                "   <dependencies>\n" .. newDependency .. "    </dependencies>\n" .. "%1",
                1
            )
        end

        if subCount == 1 then
            file = io.open(pomFile, "w")

            if not file then
                return
            end

            file:write(xmlContent)
            file:close()

            MavenToolsMainWindow.open_file(pomFile)
            MavenToolsMainWindow.refresh_entry()
        end
    end)
end

function MavenToolsMainWindow.add_local_dependency()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    local dependency = vim.fn.input("Search")

    if dependency == nil or dependency == "" then
        return
    end

    local items = {}

    for mavenInfo, projectEntry in pairs(mavenImporter.mavenEntries) do
        if mavenInfo:lower():match(dependency) then
            table.insert(items, mavenInfo)
        else
            if projectEntry.children[5] ~= nil then
                for _, dir in ipairs(projectEntry.children[5].children) do
                    if dir.textObjs[2] ~= nil then
                        if dir.textObjs[2].text:lower():match(dependency) then
                            table.insert(items, mavenInfo)
                            break
                        end
                    end
                end
            end
        end
    end

    vim.ui.select(items, {
        prompt = "Add Local Dependency (" .. entry.textObjs[2].text .. ")",
    }, function(item, idx)
        ---TODO:
        print(item, idx)
    end)
end

function MavenToolsMainWindow.download_sources()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    runner.run(
        { command = "dependency:sources" },
        mavenImporter.mavenInfoPomFile[tostring(entry.info)],
        console.console_reset,
        console.console_append
    )
end

function MavenToolsMainWindow.download_documentation()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    runner.run(
        { command = "dependency:resolve -Dclassifier=javadoc" },
        mavenImporter.mavenInfoPomFile[tostring(entry.info)],
        console.console_reset,
        console.console_append
    )
end

function MavenToolsMainWindow.download_sources_and_documentation()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    runner.run(
        { command = "dependency:sources dependency:resolve -Dclassifier=javadoc" },
        mavenImporter.mavenInfoPomFile[tostring(entry.info)],
        console.console_reset,
        console.console_append
    )
end

function MavenToolsMainWindow.toggle_hide()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    if entry.hide then
        entry.hide = nil

        local ignore = {}

        for _, v in ipairs(config.ignoreFiles) do
            if v ~= mavenImporter.mavenInfoPomFile[tostring(entry.info)] then
                table.insert(ignore, v)
            end

            ---TODO: investigate why this is here?
            config.ignoreFiles = ignore
        end
    else
        entry.hide = true

        table.insert(config.ignoreFiles, mavenImporter.mavenInfoPomFile[tostring(entry.info)])
    end

    update_main_buffer()
end

function MavenToolsMainWindow.show_all()
    showAll = not showAll

    update_main_buffer()
end

function MavenToolsMainWindow.refresh_entry()
    local line = vim.fn.line(".")
    if type(lineCallbackNew[line]) == "function" then
        lineCallbackNew[line](function(_, _, projectInfo, args)
            if projectInfo ~= nil then
                mavenImporterNew.refresh_prject(projectInfo)
            elseif args ~= nil and args.file ~= nil then
                mavenImporterNew.refresh_prject(args.file)
            end
        end)
    end
end

function MavenToolsMainWindow.show_effective_pom()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    MavenToolsImporter.effective_pom(entry, function(effectivePom)
        local editorWin = utils.get_editor_window()

        if editorWin ~= nil then
            local buf = vim.api.nvim_create_buf(false, true)

            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(effectivePom, "\n"))
            vim.api.nvim_win_set_buf(editorWin, buf)
            vim.api.nvim_buf_call(buf, function()
                vim.api.nvim_command("setfiletype xml")
            end)
        end
    end)
end

function MavenToolsMainWindow.open_file(file)
    if file ~= nil then
        local fileBuf = utils.get_file_buffer(file)

        local editorWin = utils.get_editor_window()

        if editorWin ~= nil then
            if fileBuf == nil then
                vim.api.nvim_win_call(editorWin, function()
                    vim.api.nvim_command("edit " .. file)
                end)
            else
                vim.api.nvim_win_set_buf(editorWin, fileBuf)
            end
        end
    end
end

function MavenToolsMainWindow.open_pom_file()
    local entry = get_current_entry()

    if entry == nil then
        return
    end

    local file = mavenImporter.mavenInfoPomFile[tostring(entry.info)] or entry.file

    MavenToolsMainWindow.open_file(file)
end

function MavenToolsMainWindow.show_error()
    local entry = get_current_entry()

    if entry == nil or entry.file == nil or mavenImporter.pomFileError[entry.file] == nil then
        return
    end

    local errorMsg = vim.fn.split(mavenImporter.pomFileError[entry.file], "\n")

    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, errorMsg)

    -- local editor_win = utils.get_editor_window()
    -- vim.api.width

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = 1,
        col = 1,
        width = vim.api.nvim_get_option_value("columns", {}) - 4,
        height = 10,
        style = "minimal",
        border = "rounded",
    })
end

function MavenToolsMainWindow.refresh_files()
    MavenToolsImporter.update_projects_files()
    update_main_buffer()
end

function MavenToolsMainWindow.refresh_all() end

return MavenToolsMainWindow
