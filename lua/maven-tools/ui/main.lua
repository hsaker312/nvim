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

---@class EntryInfo
---@field expanded boolean
---@field hide boolean?

---@class MavenMainWindow
MavenToolsMainWindow = {}

local prefix = "maven-tools."

---@type MavenConsoleWindow
local console = require("maven-tools.ui.console")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type MavenImporterNew
local mavenImporterNew = require(prefix .. "maven.importer_new")

---@type MavenToolsConfig
local mavenConfig = require(prefix .. "config.maven")

---@type MavenRunner
local runner = require(prefix .. "maven.runner")

---@type integer|nil
local mavenWin = nil

---@type integer|nil
local mavenBuf = nil

---@type table<integer, fun(callback:fun(entryType:TreeEntryType, entryInfo:EntryInfo?, projectInfo:ProjectInfo|nil, args:table))>
local lineCallbackNew = {}

---@class JavaFileTracker
---@field entries EntryInfo[]
---@field line integer

---@type table<string, JavaFileTracker>
local fileToEntriesMap = {}

---@type table<integer,integer?>
local lineRange = {}

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

local initialized = false

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

        ------@type table<string, EntryInfo>
        ---files = {},

        ---@type table<string, table<"files"|"tests", table<string, EntryInfo>>>
        folders = {},
    },
}

local defaultLifecycles = {
    ["clean"] = true,
    ["validate"] = true,
    ["compile"] = true,
    ["test"] = true,
    ["package"] = true,
    ["verify"] = true,
    ["install"] = true,
    ["site"] = true,
    ["deploy"] = true,
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
    vim.api.nvim_set_option_value("buftype", "nofile", {
        buf = buf,
    })

    vim.api.nvim_set_option_value("swapfile", false, {
        buf = buf,
    })
end

local key_action_map = {
    ["toggle_item"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".toggle_item()<CR>",
    ["close_main_window"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".hide_main_win()<CR>",
    ["project_filter"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".filter()<CR>",
    ["run_command"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".run()<CR>",
    ["add_dependency"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".add_dependency()<CR>",
    ["add_local_dependency"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".add_local_dependency()<CR>",
    ["download_sources"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_sources()<CR>",
    ["download_documentation"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".download_documentation()<CR>",
    ["download_sources_and_documentation"] = "<Cmd>lua require('"
        .. prefix
        .. "ui.main')"
        .. ".download_sources_and_documentation()<CR>",
    ["hide_item"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".toggle_hide()<CR>",
    ["show_all_items"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_all()<CR>",
    ["refresh_project"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".refresh_entry()<CR>",
    ["effective_pom"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_effective_pom()<CR>",
    ["open_pom"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".open_pom_file()<CR>",
    ["show_error"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".show_error()<CR>",
    ["refresh_files"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".refresh_files()<CR>",
    ["keybinds_hint"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".keybinds_hint()<CR>",
    ["add_project"] = "<Cmd>lua require('" .. prefix .. "ui.main')" .. ".add_new_project()<CR>",
}

MavenToolsMainWindow.keymap = {
    ["toggle_item"] = { "<CR>", "<2-Leftmouse>" },
    ["close_main_window"] = { "q" },
    ["project_filter"] = { "<C-f>" },
    ["run_command"] = { "<C-r>" },
    ["add_dependency"] = { "a" },
    ["add_local_dependency"] = { "A" },
    ["download_sources"] = { "ds" },
    ["download_documentation"] = { "dd" },
    ["download_sources_and_documentation"] = { "da" },
    ["hide_item"] = { "h" },
    ["show_all_items"] = { "H" },
    ["refresh_project"] = { "r" },
    ["effective_pom"] = { "ep" },
    ["open_pom"] = { "o" },
    ["show_error"] = { "e" },
    ["refresh_files"] = { "R" },
    ["keybinds_hint"] = { "?" },
    ["add_project"] = { "p" },
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
        local progress = " ["
            .. mavenImporterNew.status
            .. " "
            .. tostring(mavenImporterNew.progress()):gsub("%.%d+", "")
            .. "%]"

        table.insert(highlights, {
            highlight = "@comment",
            lineNum = lines:size(),
            colBegin = #header,
            colEnd = #header + #progress,
        })

        header = header .. progress
    elseif showAll then
        local showAllComment = " [Show All]"
        table.insert(highlights, {
            highlight = "@comment",
            lineNum = lines:size(),
            colBegin = #header,
            colEnd = #header + #showAllComment,
        })

        header = header .. showAllComment
    end

    lines:append(header)

    for i = 1, lines:size(), 1 do
        lineRange[i] = nil
    end
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
end

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
    table.insert(fileToEntriesMap[file].entries, entry)
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

    if entriesInfo.container.folders[mavenInfoStr] == nil then
        entriesInfo.container.folders[mavenInfoStr] = { files = {}, tests = {} }
    end

    local line

    if parentVisible then
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

                        fileToEntriesMap[file.path] = { line = lines:size(), entries = {} }
                        append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].files[folder])
                        -- append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
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

                        fileToEntriesMap[file.path] = { line = lines:size(), entries = {} }
                        append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].tests[folder])
                        -- append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
                        append_java_file_to_map(file.path, entriesInfo.projects[mavenInfoStr])

                        for _, parent in ipairs(parents) do
                            append_java_file_to_map(file.path, entriesInfo.projects[parent])
                        end
                    end

                    currentTab = currentTab:gsub(config.tab, "", 1)
                end
            end
        end
    elseif filter:len() == 0 then
        for folder, files in pairs(projectInfo.files) do
            if files[1] ~= nil then
                if entriesInfo.container.folders[mavenInfoStr].files[folder] == nil then
                    entriesInfo.container.folders[mavenInfoStr].files[folder] = { expanded = false }
                end

                for _, file in ipairs(files) do
                    fileToEntriesMap[file.path] = { line = lines:size(), entries = {} }
                    append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].files[folder])
                    -- append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
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
                    fileToEntriesMap[file.path] = { line = lines:size(), entries = {} }
                    append_java_file_to_map(file.path, entriesInfo.container.folders[mavenInfoStr].tests[folder])
                    -- append_java_file_to_map(file.path, entriesInfo.container.files[mavenInfoStr])
                    append_java_file_to_map(file.path, entriesInfo.projects[mavenInfoStr])

                    for _, parent in ipairs(parents) do
                        append_java_file_to_map(file.path, entriesInfo.projects[parent])
                    end
                end
            end
        end
    end
end

---@param projectInfo ProjectInfo
---@return boolean
local function show_project(projectInfo)
    if showAll then
        return true
    end

    if entriesInfo.projects[mavenImporterNew.info_to_str(projectInfo.info)].hide == nil then
        return true
    else
        return not entriesInfo.projects[mavenImporterNew.info_to_str(projectInfo.info)].hide
    end
end

---@param projectInfo ProjectInfo
---@return boolean
local function filter_project(projectInfo)
    if filter:len() == 0 then
        return true
    end

    local match = nil

    if projectInfo.name ~= nil then
        match = projectInfo.name:match(filter)
    end

    if match ~= nil then
        return true
    end

    match = mavenImporterNew.info_to_str(projectInfo.info):match(filter)

    if match ~= nil then
        return true
    end

    for package, files in pairs(projectInfo.files) do
        if package:match(filter) then
            return true
        end

        for _, file in ipairs(files) do
            if file.filename:match(filter) then
                return true
            end
        end
    end

    for package, files in pairs(projectInfo.testFiles) do
        if package:match(filter) then
            return true
        end

        for _, file in ipairs(files) do
            if file.filename:match(filter) then
                return true
            end
        end
    end

    return false
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

    if parentVisible and show_project(projectInfo) then
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

        if projectInfo.pomFile ~= nil then
            fileToEntriesMap[projectInfo.pomFile] = { line = lines:size(), entries = {} }

            for _, parent in ipairs(parents) do
                append_java_file_to_map(projectInfo.pomFile, entriesInfo.projects[parent])
            end
        end
    elseif projectInfo.pomFile ~= nil and filter:len() == 0 and show_project(projectInfo) then
        fileToEntriesMap[projectInfo.pomFile] = { line = lines:size(), entries = {} }

        for _, parent in ipairs(parents) do
            append_java_file_to_map(projectInfo.pomFile, entriesInfo.projects[parent])
        end
    end

    if entriesInfo.projects[mavenInfoStr].expanded and parentVisible and show_project(projectInfo) then
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

        if filter:len() == 0 then
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
        end
    elseif filter:len() == 0 and show_project(projectInfo) then
        generate_project_files_lines(
            currentTab .. config.tab,
            mavenInfoStr,
            projectInfo,
            lines,
            highlights,
            parents,
            false
        )

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

    fileToEntriesMap = {}

    if filter:len() == 0 and mavenImporterNew.statusCode > 2 then
        for _, pomFile in ipairs(mavenImporterNew.pomFiles) do
            if
                mavenImporterNew.pomFileToMavenInfoMap[pomFile] ~= nil
                and mavenImporterNew.pomFileIsModuleSet[pomFile] == nil
            then
                local mavenInfo = mavenImporterNew.pomFileToMavenInfoMap[pomFile].info
                local infoStr = mavenImporterNew.info_to_str(mavenInfo)
                local projectInfo = mavenImporterNew.mavenInfoToProjectInfoMap[infoStr]
                if projectInfo ~= nil then
                    generate_project_lines("", infoStr, projectInfo, lines, highlights, {}, true)
                end
            end
        end
    else
        for mavenInfoStr, projectInfo in pairs(mavenImporterNew.mavenInfoToProjectInfoMap) do
            if projectInfo ~= nil then
                generate_project_lines(
                    "",
                    mavenInfoStr,
                    projectInfo,
                    lines,
                    highlights,
                    {},
                    filter_project(projectInfo)
                )
            end
        end
    end

    for pomFile, error in pairs(mavenImporterNew.pomFileToErrorMap) do
        if error ~= nil then
            local line = ""

            line = line_cat_highlight(lines:size(), line, " ", config.projectErrorIconHighlight, highlights)
            lineRange[lines:size() + 1] = #line
            line = line_cat_highlight(lines:size(), line, "error", config.projectErrorTextHighlight, highlights)
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
    lineRange = {}

    local buf
    local setBufOptions = false

    if mavenBuf == nil then
        buf = vim.api.nvim_create_buf(false, true)
        setBufOptions = true
    else
        buf = mavenBuf
    end

    -- local lines, highlights = generate_main_buffer_lines()
    local lines, highlights = generate_main_buffer_lines_new()

    vim.api.nvim_set_option_value("modifiable", true, {
        buf = buf,
    })

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines:values())
    set_main_buffer_highlights(buf, highlights)

    vim.api.nvim_set_option_value("modifiable", false, {
        buf = buf,
    })

    if setBufOptions then
        set_main_buffer_options(buf)
        set_main_buffer_keymaps(buf)
    end

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

                    if fileToEntriesMap[bufName] ~= nil then
                        for _, entry in ipairs(fileToEntriesMap[bufName].entries) do
                            table.insert(restoreEntries, { entry = entry, value = entry.expanded })
                            entry.expanded = true
                        end

                        update_main_buffer()

                        vim.api.nvim_win_set_cursor(mavenWin, { fileToEntriesMap[bufName].line, 1 })
                    end
                end
            end,
        })
    )

    if config.autoRefreshProjectFiles then
        projectFilesUpdateTimer = vim.uv.new_timer()

        if projectFilesUpdateTimer ~= nil then
            projectFilesUpdateTimer:start(0, 10000, mavenImporterNew.refresh_projects_files)
        end
    end
end

function MavenToolsMainWindow.show_main_window()
    if mavenWin == nil then
        mavenBuf = create_main_buffer()
        mavenWin = create_main_window(mavenBuf)
        initialize_autocmds()
        update_main_buffer()
    end
end

function MavenToolsMainWindow.hide_main_win()
    if mavenWin ~= nil then
        vim.api.nvim_win_close(mavenWin, true)
    end
end

local function init()
    initialized = true
    vim.notify("Initializing Maven Tools")

    local cwd = config.cwd
    vim.api.nvim_set_hl(0, "MavenToolsContainerIcon", { fg = "#54c6f7" })
    vim.api.nvim_set_hl(0, "MavenToolsProjectIcon", { fg = "#548AF7" })
    vim.api.nvim_set_hl(0, "MavenToolsJavaPackageIcon", { fg = "#548AF7" })
    vim.api.nvim_set_hl(0, "MavenToolsJavaTestPackageIcon", { fg = "#57965C" })
    vim.api.nvim_set_hl(0, "MavenToolsJavaFileIcon", { fg = "#de7118" })

    if cwd ~= nil then
        vim.schedule(function()
            mavenImporterNew.update(cwd, update_main_buffer)
        end)
    end

    vim.api.nvim_create_user_command("MavenHideConsole", console.hide, {})
    vim.api.nvim_create_user_command("MavenShow", MavenToolsMainWindow.show_main_window, {})

    initialize_autocmds()
end

function MavenToolsMainWindow.init()
    if not initialized then
        init()
    end
end

function MavenToolsMainWindow:toggle_main_win()
    if not initialized then
        init()
    end

    if mavenWin == nil then
        MavenToolsMainWindow.show_main_window()
    else
        MavenToolsMainWindow.hide_main_win()
    end
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

                update_main_buffer()
            end
        end)
    end

    if mavenWin ~= nil then
        vim.api.nvim_win_set_cursor(mavenWin, { line, col - 1 })
    end
end

function MavenToolsMainWindow.filter()
    filter = vim.fn.input("Filter: " .. filter)

    update_main_buffer()
end

---@param callback fun(projectInfo: ProjectInfo):nil
local function select_project(callback)
    local items = {}
    local projects = {}

    for _, pomFile in ipairs(mavenImporterNew.pomFiles) do
        if mavenImporterNew.pomFileToMavenInfoMap[pomFile] ~= nil then
            local mavenInfo = mavenImporterNew.pomFileToMavenInfoMap[pomFile].info
            local infoStr = mavenImporterNew.info_to_str(mavenInfo)
            local projectInfo = mavenImporterNew.mavenInfoToProjectInfoMap[infoStr]
            if projectInfo ~= nil then
                table.insert(items, projectInfo.name)
                table.insert(projects, projectInfo)
            end
        end
    end

    vim.ui.select(items, {
        prompt = "Select Project",
    }, function(_, idx)
        if idx ~= nil then
            callback(projects[idx])
        end
    end)
end

function MavenToolsMainWindow.run(cmd)
    local callback = function(_, _, projectInfo, _)
        if projectInfo ~= nil then
            local commands = {}

            for _, command in ipairs(config.lifecycleCommands) do
                if defaultLifecycles[command] == nil then
                    table.insert(commands, command)
                end
            end

            for command, _ in pairs(defaultLifecycles) do
                table.insert(commands, command)
            end

            for _, plugin in ipairs(projectInfo.plugins) do
                local pluginInfoStr = mavenImporterNew.info_to_str(plugin)

                for _, command in ipairs(mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr].commands) do
                    table.insert(commands, mavenImporterNew.pluginInfoToPluginMap[pluginInfoStr].goal .. ":" .. command)
                end
            end

            vim.ui.select(commands, {
                prompt = "Run (" .. projectInfo.name .. ")",
            }, function(command)
                if command == nil then
                    return
                end

                runner.run({ command = command }, projectInfo.pomFile, console.console_reset, console.console_append)
            end)
        end
    end

    if cmd == nil then
        local line = vim.fn.line(".")

        if lineCallbackNew[line] ~= nil then
            lineCallbackNew[line](callback)
        end
    else
        if not initialized then
            init()
            return
        end

        select_project(function(projectInfo)
            callback(nil, nil, projectInfo)
        end)
    end
end

---TODO: move to utils
---@param url string
---@param callback fun(err:any, content:string|nil):any
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

---@param projectInfo ProjectInfo
---@param dependency string
---@param callback fun(groupId:string, artifactId:string, version:string)
---@param start integer|nil
local function select_package(projectInfo, dependency, callback, start)
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
                prompt = "Add Dependency (" .. projectInfo.name .. ")",
            }, function(item, idx)
                if item == nil or idx == nil then
                    return
                end

                if idx <= count then
                    select_package_version(agPairs[item].g, agPairs[item].a, callback)
                else
                    select_package(projectInfo, dependency, callback, current + requestRows)
                end
            end)
        end
    )
end

local function add_dependency_to_pom_file(pomFile, groupId, artifactId, version)
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
end

function MavenToolsMainWindow.keybinds_hint()
    local buf = vim.api.nvim_create_buf(false, true)

    local lines = {}
    local maxLineLen = 0
    ---@type string[]
    local linesLeft = {}
    local maxLineLeft = 0
    local linesRight = {}
    local maxLineRight = 0
    local linesCount = 0

    for k, v in pairs(MavenToolsMainWindow.keymap) do
        table.insert(linesLeft, k)
        maxLineLeft = math.max(maxLineLeft, #k)

        local lineRight = ""
        for _, key in ipairs(v) do
            lineRight = lineRight .. key .. "  "
        end

        lineRight = lineRight:gsub("..$", "")
        table.insert(linesRight, lineRight)
        maxLineRight = math.max(maxLineRight, #lineRight)
    end

    for i, leftLine in ipairs(linesLeft) do
        lines[i] = string.rep(" ", maxLineLeft - #leftLine + 1)
            .. leftLine
            .. " : "
            .. linesRight[i]
            .. string.rep(" ", maxLineRight - #linesRight[i] + 1)
        maxLineLen = math.max(maxLineLen, #lines[i])
        linesCount = i
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = 1,
        col = 1,
        width = maxLineLen,
        height = linesCount,
        style = "minimal",
        border = "rounded",
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>quit<cr>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_set_option_value("number", false, {
        win = win,
    })

    vim.api.nvim_set_option_value("rnu", false, {
        win = win,
    })

    vim.api.nvim_set_option_value("spell", false, {
        win = win,
    })

    vim.api.nvim_set_option_value("buftype", "nofile", {
        buf = buf,
    })

    vim.api.nvim_set_option_value("swapfile", false, {
        buf = buf,
    })

    vim.api.nvim_set_option_value("modifiable", false, {
        buf = buf,
    })
end

---@param projectInfo ProjectInfo
function MavenToolsMainWindow.add_dependency_new(projectInfo)
    if projectInfo == nil then
        return
    end

    local dependency = vim.fn.input("Search")

    if dependency == nil or dependency == "" then
        return
    end

    select_package(projectInfo, dependency, function(groupId, artifactId, version)
        add_dependency_to_pom_file(projectInfo.pomFile, groupId, artifactId, version)
    end)
end

function MavenToolsMainWindow.add_dependency(cmd)
    local callback = function(_, _, projectInfo, _)
        if projectInfo ~= nil then
            MavenToolsMainWindow.add_dependency_new(projectInfo)
        end
    end

    if cmd == nil then
        local line = vim.fn.line(".")

        if lineCallbackNew[line] ~= nil then
            lineCallbackNew[line](callback)
        end
    else
        if not initialized then
            init()
            return
        end

        select_project(function(projectInfo)
            callback(nil, nil, projectInfo)
        end)
    end
end

function MavenToolsMainWindow.add_local_dependency(cmd)
    local callback = function(_, _, projectInfo, _)
        if projectInfo ~= nil then
            local projectInfoStr = mavenImporterNew.info_to_str(projectInfo.info)
            local items = {}

            for mavenInfo, _ in pairs(mavenImporterNew.mavenInfoToProjectInfoMap) do
                if mavenInfo ~= projectInfoStr then
                    table.insert(items, mavenInfo)
                end
            end

            vim.ui.select(items, {
                prompt = "Add Local Dependency (" .. projectInfo.name .. ")",
            }, function(item, _)
                if item ~= nil then
                    local dependencyInfo = mavenImporterNew.mavenInfoToProjectInfoMap[item].info
                    add_dependency_to_pom_file(
                        projectInfo.pomFile,
                        dependencyInfo.groupId,
                        dependencyInfo.artifactId,
                        dependencyInfo.version
                    )
                end
            end)
        end
    end

    if cmd == nil then
        local line = vim.fn.line(".")

        if lineCallbackNew[line] ~= nil then
            lineCallbackNew[line](callback)
        end
    else
        if not initialized then
            init()
            return
        end

        select_project(function(projectInfo)
            callback(nil, nil, projectInfo)
        end)
    end
end

function MavenToolsMainWindow.download_sources()
    local line = vim.fn.line(".")

    if lineCallbackNew[line] ~= nil then
        lineCallbackNew[line](function(_, _, projectInfo, _)
            if projectInfo == nil or projectInfo.pomFile == nil then
                return
            end

            runner.run(
                { command = "dependency:sources" },
                projectInfo.pomFile,
                console.console_reset,
                console.console_append
            )
        end)
    end
end

function MavenToolsMainWindow.download_documentation()
    local line = vim.fn.line(".")

    if lineCallbackNew[line] ~= nil then
        lineCallbackNew[line](function(_, _, projectInfo, _)
            if projectInfo == nil or projectInfo.pomFile == nil then
                return
            end

            runner.run(
                { command = "dependency:resolve -Dclassifier=javadoc" },
                projectInfo.pomFile,
                console.console_reset,
                console.console_append
            )
        end)
    end
end

function MavenToolsMainWindow.download_sources_and_documentation()
    local line = vim.fn.line(".")

    if lineCallbackNew[line] ~= nil then
        lineCallbackNew[line](function(_, _, projectInfo, _)
            if projectInfo == nil or projectInfo.pomFile == nil then
                return
            end

            runner.run(
                { command = "dependency:sources dependency:resolve -Dclassifier=javadoc" },
                projectInfo.pomFile,
                console.console_reset,
                console.console_append
            )
        end)
    end
end

function MavenToolsMainWindow.toggle_hide()
    local line = vim.fn.line(".")

    if lineCallbackNew[line] ~= nil then
        lineCallbackNew[line](function(_, _, projectInfo, _)
            if projectInfo ~= nil and projectInfo.info ~= nil then
                local infoStr = mavenImporterNew.info_to_str(projectInfo.info)
                if entriesInfo.projects[infoStr].hide == nil then
                    entriesInfo.projects[infoStr].hide = true
                else
                    entriesInfo.projects[infoStr].hide = not entriesInfo.projects[infoStr].hide
                end

                update_main_buffer()
            end
        end)
    end
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
                mavenImporterNew.refresh_project(projectInfo)
            elseif args ~= nil and args.file ~= nil then
                mavenImporterNew.refresh_project(args.file)
            end
        end)
    end
end

function MavenToolsMainWindow.show_effective_pom()
    local line = vim.fn.line(".")

    if lineCallbackNew[line] then
        lineCallbackNew[line](function(_, _, projectInfo, _)
            if projectInfo ~= nil and projectInfo.pomFile ~= nil then
                local taskMgr = utils.Task_Mgr()

                vim.notify("Fetching effective pom for project: " .. projectInfo.name)

                taskMgr:run(
                    mavenConfig.importer_pipe_cmd(projectInfo.pomFile, { "help:effective-pom" }),
                    function(effectivePom)
                        local effectivePomStr = mavenImporterNew.extract_effective_pom(effectivePom)

                        if effectivePomStr == nil then
                            return
                        end

                        local lines = {}

                        for lineStr in effectivePomStr:gmatch("[^\r\n]+") do
                            table.insert(lines, lineStr)
                        end

                        vim.schedule(function()
                            local editorWin = utils.get_editor_window()

                            if editorWin ~= nil then
                                local buf = vim.api.nvim_create_buf(false, true)

                                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                                vim.api.nvim_win_set_buf(editorWin, buf)
                                vim.api.nvim_buf_call(buf, function()
                                    vim.api.nvim_command("setfiletype xml")
                                end)
                            end
                        end)
                    end
                )
            end
        end)
    end
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
    local line = vim.fn.line(".")

    if lineCallbackNew[line] ~= nil then
        lineCallbackNew[line](function(_, _, projectInfo, _)
            if projectInfo ~= nil and projectInfo.pomFile ~= nil then
                utils.open_file(projectInfo.pomFile)
            end
        end)
    end
end

function MavenToolsMainWindow.show_error()
    local line = vim.fn.line(".")

    if lineCallbackNew[line] ~= nil then
        lineCallbackNew[line](function(_, _, _, args)
            if args.error == nil then
                return
            end

            local errorMsg = vim.fn.split(args.error, "\n")

            local buf = vim.api.nvim_create_buf(false, true)

            vim.api.nvim_buf_set_lines(buf, 0, -1, false, errorMsg)

            local win = vim.api.nvim_open_win(buf, true, {
                relative = "cursor",
                row = 1,
                col = 1,
                width = vim.api.nvim_get_option_value("columns", {}) - 10,
                height = vim.api.nvim_get_option_value("lines", {}) - 12,
                style = "minimal",
                border = "rounded",
            })
        end)
    end
end

function MavenToolsMainWindow.refresh_files()
    mavenImporterNew.refresh_projects_files()
end

function MavenToolsMainWindow.add_new_project()
    local pomFile = vim.fn.input("Path to pom.xml file")

    mavenImporterNew.add_new_project(pomFile)
end

function MavenToolsMainWindow.refresh_all()
    ---TODO: implement
end

return MavenToolsMainWindow
