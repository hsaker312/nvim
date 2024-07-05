---@class Text_Obj
---@field text string
---@field hl string

---@class Tree_Entry
---@field show_always boolean
---@field text_objs Text_Obj[]
---@field expanded boolean|nil
---@field children Tree_Entry[]|table<string, Tree_Entry>
---@field callback "0"|"1"|"2"
---@field command string|nil
---@field module integer
---@field modules Tree_Entry|nil
---@field info Maven_Info|nil
---@field file string|nil
---@field error integer|nil

---@class Maven_Project
---@field project_info Maven_Info
---@field entry Tree_Entry
---@field plugins Maven_Info[]
---@field modules string[]
---@field parent Maven_Info|nil

---@class File_Index
---@field index integer
---@field checksum string|nil

---@class File_Info_Checksum
---@field info Maven_Info|nil
---@field checksum string

---@class Pending_Plugin
---@field info Maven_Info
---@field plugin_info Maven_Info

---@class Pending_Module
---@field info Maven_Info
---@field module_path string

---@class Importer
Importer = {}

local maven_info = {}

local cwd
local state = ""

---@param group_id string
---@param artifact_id string
---@param version string|nil
---@param name string|nil
---@return Maven_Info
function maven_info:new(group_id, artifact_id, version, name)
    ---@class Maven_Info
    ---@field group_id string
    ---@field artifact_id string
    ---@field version string
    ---@field name string|nil
    local res = { group_id = group_id or "", artifact_id = artifact_id or "", version = version or "", name = name }

    setmetatable(res, {
        __tostring = function(obj)
            return obj.group_id .. ":" .. obj.artifact_id .. ":" .. obj.version
        end,
    })

    return res
end

local prefix = "maven-tools."

---@type Utils
local utils = require(prefix .. "utils")

---@type Config
local config = require(prefix .. "config.config")

---@type Maven_Config
local maven_config = require(prefix .. "config.maven")

local xml2lua = require("maven-tools.deps.xml2lua.xml2lua")
local xmlTreeHandler = require("maven-tools.deps.xml2lua.xmlhandler.tree")

---@type table<string, Tree_Entry|nil>
Importer.Maven_Entries = {}

---@type table<string, string|nil>
Importer.Maven_Info_Pom_File = {}

---@type table<string, File_Info_Checksum|nil>
Importer.Pom_File_Maven_Info = {}

---@type table<string, string>
Importer.Pom_File_Error = {}

---@type Task_Mgr
local task_mgr = utils.Task_Mgr()

---@type function
local update_callback = function(...) end

---@type Array
Importer.pom_files = utils.Array()

---@type table<string, Tree_Entry|"pending"|nil>
local plugins_cache = {}

---@type Pending_Plugin[]
local pending_plugins = {}

--- parent - modules
---@type table<string, Maven_Info[]|nil>
local modules_tree = {}

---@type table<string, Array|nil>
local pending_modules = {}

---@type string[]
local lifecycles = {
    "clean",
    "validate",
    "compile",
    "test",
    "package",
    "verify",
    "install",
    "site",
    "deploy",
}

---@return boolean
Importer.idle = function()
    return task_mgr:idle()
end

--- @return number
Importer.progress = function()
    return task_mgr:progress()
end

local function reset()
    Importer.Maven_Entries = {}

    Importer.Maven_Info_Pom_File = {}

    Importer.Pom_File_Maven_Info = {}
end

---@return Tree_Entry
local function make_lifecycle_entry()
    ---@type Tree_Entry
    local res = {
        show_always = false,
        text_objs = { { text = "󱂀 ", hl = "@label" }, { text = "Lifecycle", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
        module = 0,
    }

    for i, lifecycle in ipairs(lifecycles) do
        ---@type Tree_Entry
        local item = {
            show_always = true,
            text_objs = { { text = " ", hl = "@label" }, { text = lifecycle, hl = "@text" } },
            command = lifecycle,
            expanded = false,
            children = {},
            callback = "1",
            module = 0,
        }

        res.children[i] = item
    end

    return res
end

---@return Tree_Entry
local function make_plugins_entry()
    return {
        show_always = false,
        text_objs = { { text = "󱧽 ", hl = "@label" }, { text = "Plugins", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
    }
end

---@return Tree_Entry
local function make_dependencies_entry()
    return {
        show_always = false,
        text_objs = { { text = " ", hl = "@label" }, { text = "Dependencies", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
    }
end

---@return Tree_Entry
local function make_repositories_entry()
    return {
        show_always = false,
        text_objs = { { text = " ", hl = "@label" }, { text = "Repositories", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
    }
end

---@return Maven_Info
local function extract_plugin_info(plugin)
    return maven_info:new(plugin.groupId or "org.apache.maven.plugins", plugin.artifactId, plugin.version)
end

---@return Text_Obj[]
local function extract_dependency(dependency)
    local res = {}
    local count = 0

    if type(dependency.groupId) == "string" then
        table.insert(res, { text = dependency.groupId, hl = "@text" })
        count = count + 1
    end

    if count > 0 then
        table.insert(res, { text = ":", hl = "@text" })
    end

    if type(dependency.artifactId) == "string" then
        table.insert(res, { text = dependency.artifactId, hl = "@text" })
    end

    if count > 0 then
        table.insert(res, { text = ":", hl = "@text" })
    end

    if type(dependency.version) == "string" then
        table.insert(res, { text = dependency.version, hl = "@text" })
    end

    return res
end

---@return Text_Obj[]
local function extract_repository(repository)
    local res = {}

    if type(repository.id) == "string" and type(repository.url) == "string" then
        table.insert(res, { text = repository.id, hl = "@text" })
        table.insert(res, { text = " ", hl = "@text" })
        table.insert(res, { text = "(" .. repository.url .. ")", hl = "Comment" })
    end

    return res
end

---@param pom_file string
---@param info Maven_Info
---@param callback fun(plugin: Plugin?):nil
local function process_plugin(pom_file, info, callback)
    local cmd = "help:describe "

    if info.group_id ~= "" then
        cmd = cmd .. '"-DgroupId=' .. info.group_id .. '" '
    end

    if info.artifact_id ~= "" then
        cmd = cmd .. '"-DartifactId=' .. info.artifact_id .. '" '
    end

    if info.version ~= "" then
        cmd = cmd .. '"-Dversion=' .. info.version .. '"'
    end

    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(pom_file, {
            cmd,
        }),
        ---@param pipe_res string
        ---@diagnostic disable-next-line: redefined-local
        function(pipe_res)
            local plugin = nil

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("ERROR") then
                    break
                end

                if plugin == nil then
                    if line:match("Goal Prefix: ") then
                        plugin = {
                            goal = line:gsub("Goal Prefix: ", ""):gsub("\n", ""),
                            commands = {},
                        }
                    end
                else
                    if line:match("^" .. plugin.goal .. ":") then
                        table.insert(plugin.commands, { line:gsub(plugin.goal .. ":", ""):gsub("\n", "") })
                    end
                end
            end

            callback(plugin)
        end
    )
end

---@param project table
---@return Maven_Info[]
local function process_project_plugins(project)
    ---@type Maven_Info[]
    local plugins = {}

    if project.build ~= nil and project.build.plugins ~= nil and project.build.plugins.plugin ~= nil then
        if project.build.plugins.plugin[1] ~= nil then
            for _, plugin in pairs(project.build.plugins.plugin) do
                table.insert(plugins, extract_plugin_info(plugin))
            end
        else
            table.insert(plugins, extract_plugin_info(project.build.plugins.plugin))
        end
    end

    return plugins
end

---@param project table
---@param entry Tree_Entry
local function process_project_dependencies(project, entry)
    if project.dependencies ~= nil and project.dependencies.dependency ~= nil then
        if project.dependencies.dependency[1] ~= nil then
            for _, dependency in pairs(project.dependencies.dependency) do
                local dep = extract_dependency(dependency)

                if dep[1] ~= nil then
                    ---@type Tree_Entry
                    local dep_entry = {
                        show_always = true,
                        text_objs = { { text = " ", hl = "@label" } },
                        expanded = false,
                        children = {},
                        callback = "2",
                        module = 0,
                    }

                    dep_entry.text_objs = utils.array_join(dep_entry.text_objs, dep)

                    table.insert(entry.children[3].children, dep_entry)
                end
            end
        else
            local dep = extract_dependency(project.dependencies.dependency)

            if dep[1] ~= nil then
                ---@type Tree_Entry
                local dep_entry = {
                    show_always = true,
                    text_objs = { { text = " ", hl = "@label" } },
                    expanded = false,
                    children = {},
                    callback = "2",
                    module = 0,
                }

                dep_entry.text_objs = utils.array_join(dep_entry.text_objs, dep)

                table.insert(entry.children[3].children, dep_entry)
            end
        end
    end
end

---@param project table
---@param entry Tree_Entry
local function process_project_repositories(project, entry)
    if project.repositories ~= nil and project.repositories.repository ~= nil then
        if project.repositories.repository[1] ~= nil then
            for _, repository in pairs(project.repositories.repository) do
                local repo = extract_repository(repository)

                if repo[1] ~= nil then
                    ---@type Tree_Entry
                    local repo_entry = {
                        show_always = true,
                        text_objs = { { text = "󰳐 ", hl = "@label" } },
                        callback = "2",
                        expanded = false,
                        children = {},
                        module = 0,
                    }

                    repo_entry.text_objs = utils.array_join(repo_entry.text_objs, repo)

                    table.insert(entry.children[4].children, repo_entry)
                end
            end
        else
            local repo = extract_repository(project.repositories.repository)

            if repo[1] ~= nil then
                ---@type Tree_Entry
                local repo_entry = {
                    show_always = true,
                    text_objs = { { text = "󰳐 ", hl = "@label" } },
                    callback = "2",
                    expanded = false,
                    children = {},
                    module = 0,
                }

                repo_entry.text_objs = utils.array_join(repo_entry.text_objs, repo)

                table.insert(entry.children[4].children, repo_entry)
            end
        end
    end
end

---@param project table
---@param entry Tree_Entry
---@return string[]
local function process_project_modules(project, entry)
    ---@type string[]
    local modules = {}

    if project.modules ~= nil and project.modules.module ~= nil then
        entry.modules = {
            show_always = true,
            text_objs = { { text = "󱧷 ", hl = "@label" }, { text = "Modules", hl = "@text" } },
            expanded = false,
            children = {},
            callback = "0",
            module = 0,
        }

        if project.modules.module[1] ~= nil then
            for _, module in pairs(project.modules.module) do
                table.insert(modules, module)
            end
        else
            table.insert(modules, project.modules.module)
        end
    end

    return modules
end

---@param pom_file string
---@param refresh_project_info Maven_Info|nil
---@param error string
local function error_project_entry(pom_file, refresh_project_info, error)
    if refresh_project_info ~= nil then
        Importer.Pom_File_Maven_Info[pom_file] = nil
        Importer.Maven_Info_Pom_File[tostring(refresh_project_info)] = nil
        Importer.Maven_Entries[tostring(refresh_project_info)] = nil
    end

    local dir = cwd:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    if dir:sub(#dir, #dir) ~= "/" then
        dir = dir .. "/"
    end

    local relative_path = pom_file:gsub(dir, "")

    Importer.Maven_Entries[pom_file] = {
        show_always = true,
        text_objs = {
            { text = " ", hl = "@label" },
            { text = "error", hl = "DiagnosticUnderlineError" },
            { text = " ", hl = "@text" },
            {
                text = "(" .. relative_path .. ")",
                hl = "Comment",
            },
        },
        expanded = false,
        callback = "0",
        children = {},
        module = 0,
        file = pom_file,
    }

    Importer.Pom_File_Error[pom_file] = error
end

---comment
---@param xml any
---@param str string
---@return string|nil
local function substitute(xml, str)
    if xml == nil or str == nil then
        return nil
    end

    local res = str

    for var in str:gmatch("%${(.-)}") do
        local value = xml.root.project[var:gsub("project.", "")]

        if value == nil and type(xml.root.project.properties) == "table" then
            value = xml.root.project.properties[var:gsub("project%.", ""):gsub("properties%.", "")]
        end

        res = res:gsub("%${" .. var .. "}", value or var)
    end

    if res:match("%${.-}") then
        return substitute(xml, res)
    end

    return res
end

---@param pom_file string
---@param refresh_project_info Maven_Info|nil
---@return Maven_Info|nil
local function get_project_info(pom_file, refresh_project_info)
    local pom_file_handle = io.open(pom_file, "r")
    local project_info = nil

    if pom_file_handle ~= nil then
        local pom_file_str = pom_file_handle:read("*a")
        pom_file_handle:close()

        local pomXml = xmlTreeHandler:new()
        local pomParser = xml2lua.parser(pomXml)
        pomParser:parse(pom_file_str)

        local groupId = substitute(pomXml, pomXml.root.project.groupId)
        local artifactId = substitute(pomXml, pomXml.root.project.artifactId)
        local version = substitute(pomXml, pomXml.root.project.version)
        local name = substitute(pomXml, pomXml.root.project.name)

        if groupId ~= nil and artifactId ~= nil then
            project_info = maven_info:new(groupId, artifactId, version, name)

            Importer.Maven_Info_Pom_File[tostring(project_info)] = pom_file
            Importer.Pom_File_Maven_Info[pom_file] =
                { info = project_info, checksum = tostring(utils.file_checksum(pom_file)) }

            if refresh_project_info ~= nil and tostring(refresh_project_info) ~= tostring(project_info) then
                Importer.Maven_Info_Pom_File[tostring(refresh_project_info)] = nil
                Importer.Maven_Entries[tostring(refresh_project_info)] = nil
            end
        end
    end

    return project_info
end

---@param project table
---@param refresh_project_info Maven_Info|nil
---@return Maven_Project|nil
local function process_project(project, refresh_project_info)
    ---@type Tree_Entry
    local entry = {
        show_always = true,
        text_objs = { { text = " ", hl = "@label" } },
        expanded = false,
        callback = "0",
        children = {
            make_lifecycle_entry(),
            make_plugins_entry(),
            make_dependencies_entry(),
            make_repositories_entry(),
        },
        modules = nil,
        module = 0,
    }
    if refresh_project_info ~= nil then
        if Importer.Maven_Entries[tostring(refresh_project_info)] then
            entry.module = Importer.Maven_Entries[tostring(refresh_project_info)].module
        end
    end

    if
        type(project.groupId) == "string"
        and type(project.artifactId) == "string"
        and type(project.version) == "string"
    then
        local project_info = maven_info:new(project.groupId, project.artifactId, project.version)

        if Importer.Maven_Entries[tostring(project_info)] ~= nil and refresh_project_info == nil then
            return nil
        end

        entry.info = project_info

        table.insert(entry.text_objs, {
            text = Importer.Pom_File_Maven_Info[Importer.Maven_Info_Pom_File[tostring(project_info)]].info.name
                or project.artifactId,
            hl = "@text",
        })

        ---@type Maven_Info|nil
        local parent = nil

        if
            project.parent ~= nil
            and project.parent.groupId ~= nil
            and project.parent.artifactId ~= nil
            and project.parent.version ~= nil
        then
            parent = maven_info:new(project.parent.groupId, project.parent.artifactId, project.parent.version)
        end

        local plugins = process_project_plugins(project)

        process_project_dependencies(project, entry)

        process_project_repositories(project, entry)

        local modules = process_project_modules(project, entry)

        return { project_info = project_info, entry = entry, plugins = plugins, modules = modules, parent = parent }
    end
end

---@param pom_file string
---@param refresh_project_info Maven_Info|nil
---@param callback fun(maven_project: Maven_Project|nil)
local function process_pom_file_task(pom_file, refresh_project_info, callback)
    local xmlTree = xmlTreeHandler:new()
    local parser = xml2lua.parser(xmlTree)

    task_mgr:run(pom_file, maven_config.importer_pipe_cmd(pom_file, { "help:effective-pom" }), function(xml)
        local start = xml:find("<projects")

        ---@type integer|nil
        local finish = nil

        ---@type string
        local finishTag = nil

        if start ~= nil then
            finishTag = "</projects>"
        else
            start = xml:find("<project")

            finishTag = "</project>"
        end

        finish = xml:find(finishTag)

        if start ~= nil and finish ~= nil then
            finish = finish + #finishTag
            local projectXml = xml:sub(start, finish)

            parser:parse(projectXml)

            if xmlTree.root.projects ~= nil and xmlTree.root.projects.project ~= nil then
                if xmlTree.root.projects.project[1] ~= nil then
                    for _, project in pairs(xmlTree.root.projects.project) do
                        callback(process_project(project, refresh_project_info))
                    end
                else
                    callback(process_project(xmlTree.root.projects.project, refresh_project_info))
                end
            elseif xmlTree.root.project then
                callback(process_project(xmlTree.root.project, refresh_project_info))
            else
                callback(nil)
            end
        else
            error_project_entry(pom_file, refresh_project_info, xml)
            callback(nil)
        end
    end)
end

local function process_pending_plugins()
    ---@type table<string, fun()[]|nil>
    local process_plugin_assignments = {}

    local process_plugins_queue = utils.Queue()

    for _, pending_plugin in ipairs(pending_plugins) do
        local plugin_id = tostring(pending_plugin.plugin_info)

        if process_plugin_assignments[plugin_id] == nil then
            process_plugin_assignments[plugin_id] = {}
        end

        if plugins_cache[plugin_id] == nil then
            plugins_cache[plugin_id] = "pending"

            process_plugins_queue:push({
                Importer.Maven_Info_Pom_File[tostring(pending_plugin.info)],
                pending_plugin.plugin_info,
                function(callback_res)
                    if callback_res == nil then
                        return
                    end

                    ---@type Tree_Entry
                    local plugin_entry = {
                        show_always = true,
                        text_objs = { { text = " ", hl = "@label" }, { text = callback_res.goal, hl = "@text" } },
                        expanded = false,
                        children = {},
                        callback = "0",
                        module = 0,
                    }

                    for _, command in ipairs(callback_res.commands) do
                        ---@type Tree_Entry
                        local plugin_command_entry = {
                            show_always = true,
                            text_objs = { { text = " ", hl = "@label" }, { text = command[1], hl = "@text" } },
                            command = callback_res.goal .. ":" .. command[1],
                            expanded = false,
                            children = {},
                            callback = "1",
                            module = 0,
                        }

                        table.insert(plugin_entry.children, plugin_command_entry)
                    end

                    plugins_cache[plugin_id] = plugin_entry

                    table.insert(
                        Importer.Maven_Entries[tostring(pending_plugin.info)].children[2].children,
                        utils.deepcopy(plugin_entry)
                    )

                    if process_plugin_assignments[plugin_id] ~= nil then
                        for _, pending_callback in ipairs(process_plugin_assignments[plugin_id]) do
                            pending_callback()
                        end
                    end

                    update_callback()
                end,
            })
        else
            table.insert(process_plugin_assignments[plugin_id], function()
                table.insert(
                    Importer.Maven_Entries[tostring(pending_plugin.info)].children[2].children,
                    utils.deepcopy(plugins_cache[plugin_id])
                )
            end)
        end
    end

    local task = process_plugins_queue:pop()

    if task == nil then
        for _, pending_callbacks in pairs(process_plugin_assignments) do
            for _, pending_callback in ipairs(pending_callbacks) do
                pending_callback()
            end
        end
    end

    while task ~= nil do
        process_plugin(task[1], task[2], task[3])

        task = process_plugins_queue:pop()
    end
end

local function process_pending_modules_tree()
    for parent, modules in pairs(modules_tree) do
        local parentEntry = Importer.Maven_Entries[parent]

        if parentEntry ~= nil then
            for _, module in ipairs(modules) do
                local module_entry = Importer.Maven_Entries[tostring(module)]
                local module_file = Importer.Maven_Info_Pom_File[tostring(module)]

                if module_entry ~= nil and module_file ~= nil then
                    if pending_modules[module_file] ~= nil then
                        pending_modules[module_file]:remove_value(parent)
                    end

                    if parentEntry.modules ~= nil then
                        module_entry.module = module_entry.module + 1

                        parentEntry.modules.children[tostring(module)] = module_entry
                    end
                end
            end
        end
    end
end

local function process_pending_modules()
    for module_file, parents in pairs(pending_modules) do
        if parents:size() > 0 then
            local module_info = nil

            if Importer.Pom_File_Maven_Info[module_file] ~= nil then
                module_info = Importer.Pom_File_Maven_Info[module_file].info
            else
                module_info = get_project_info(module_file)
            end

            if module_info ~= nil then
                local module_entry = Importer.Maven_Entries[tostring(module_info)]

                if module_entry ~= nil then
                    for _, parent in ipairs(parents) do
                        module_entry.module = module_entry.module + 1

                        Importer.Maven_Entries[parent].modules.children[tostring(module_info)] = module_entry
                    end
                end
            end
        end
    end
end

---@return boolean
local function is_pending()
    for _, _ in ipairs(pending_plugins) do
        return true
    end

    for _, _ in ipairs(modules_tree) do
        return true
    end

    for _, _ in ipairs(pending_modules) do
        return true
    end

    return false
end

local function process_pending()
    process_pending_plugins()
    pending_plugins = {}

    process_pending_modules_tree()
    modules_tree = {}

    update_callback()

    process_pending_modules()

    pending_modules = {}

    if task_mgr:idle() then
        task_mgr:trigger_idle_callback()
    end
end

---@param pom_file string
---@param refresh_project_info Maven_Info|nil
local function process_pom_file(pom_file, refresh_project_info)
    local file_info = Importer.Pom_File_Maven_Info[pom_file]

    ---@type Maven_Info|nil
    local project_info = nil

    if file_info ~= nil then
        project_info = file_info.info
    end

    if project_info ~= nil then
        if Importer.Maven_Entries[tostring(project_info)] ~= nil and refresh_project_info == nil then
            return nil
        end

        process_pom_file_task(pom_file, refresh_project_info, function(maven_project)
            if maven_project ~= nil then
                Importer.Maven_Entries[tostring(maven_project.project_info)] = maven_project.entry

                for _, info in ipairs(maven_project.plugins) do
                    ---@type Pending_Plugin
                    local pending_plugin = { info = maven_project.project_info, plugin_info = info }

                    table.insert(pending_plugins, pending_plugin)
                end

                for _, module in ipairs(maven_project.modules) do
                    local module_file = utils
                        .Path(Importer.Maven_Info_Pom_File[tostring(maven_project.project_info)])
                        :dirname()
                        :join(module)
                        :join("pom.xml").str

                    if pending_modules[module_file] == nil then
                        pending_modules[module_file] = utils.Array()
                    end

                    pending_modules[module_file]:append(tostring(maven_project.project_info))
                end

                if maven_project.parent ~= nil then
                    local parent_id = tostring(maven_project.parent)

                    if modules_tree[parent_id] == nil then
                        modules_tree[parent_id] = { maven_project.project_info }
                    else
                        table.insert(modules_tree[parent_id], maven_project.project_info)
                    end
                end
            end

            update_callback()
        end)
    end
end

---@return table<string, File_Info_Checksum|nil>
---@return table<string, Tree_Entry|nil>
local function read_cache_file()
    local config_path = vim.fn.stdpath("config")

    if type(config_path) == "table" then
        config_path = config_path[1]
    end

    local res_file = io.open(utils.Path(config_path):join(".maven").str .. "/plugins.cache.json", "r")

    if res_file then
        local res_str = res_file:read("*a")
        res_file:close()

        plugins_cache = vim.fn.json_decode(res_str)
    end

    ---@type table<string, File_Info_Checksum|nil>
    local cached_files

    ---@type table<string, Tree_Entry|nil>
    local cached_entries

    res_file = io.open(utils.Path(cwd):join(config.local_config_dir):join("cache.json").str, "r")

    if res_file then
        local res_str = res_file:read("*a")
        res_file:close()
        local cache = vim.fn.json_decode(res_str)

        if
            cache.version ~= nil
            and cache.checksum ~= nil
            and cache.version == config.version
            and cache.checksum == maven_config.importer_checksum()
        then
            cached_files = cache.files
            cached_entries = cache.entries
        end
    end

    return cached_files, cached_entries
end

local function write_plugins_cache_file()
    local config_path = vim.fn.stdpath("config")

    if type(config_path) == "table" then
        config_path = config_path[1]
    end

    local path = utils.Path(config_path):join(".maven").str
    local success, _ = utils.create_directories(path)

    if success then
        local res_file = io.open(path .. "/plugins.cache.json", "r")

        if res_file then
            vim.schedule(function()
                local global_plugins_cache = vim.fn.json_decode(res_file:read("*a"))
                res_file:close()

                plugins_cache = utils.table_join(global_plugins_cache, plugins_cache)

                res_file = io.open(path .. "/plugins.cache.json", "w")

                if res_file then
                    res_file:write(vim.fn.json_encode(plugins_cache))
                    res_file:close()
                end
            end)
        else
            vim.schedule(function()
                res_file = io.open(path .. "/plugins.cache.json", "w")

                if res_file then
                    res_file:write(vim.fn.json_encode(plugins_cache))
                    res_file:close()
                end
            end)
        end
    end
end

local function write_cache_file()
    local path = utils.Path(cwd):join(config.local_config_dir).str
    local success, _ = utils.create_directories(path)
    print("dir created: ", success)

    if success then
        local res_file = io.open(path .. "/cache.json", "w")

        if res_file then
            print("cache file opend")
            vim.schedule(function()
                res_file:write(vim.fn.json_encode({
                    version = config.version,
                    checksum = maven_config.importer_checksum(),
                    files = Importer.Pom_File_Maven_Info,
                    entries = Importer.Maven_Entries,
                }))

                res_file:close()
            end)
        end
    end

    write_plugins_cache_file()
end

---@param cached_entry Tree_Entry
---@param cached_files table<string, File_Info_Checksum|nil>
---@return boolean
local function validate_cached_entry_modules_checksum(cached_entry, cached_files)
    ---@type table<string, boolean|nil>
    local modules_info = {}

    if cached_entry.modules ~= nil then
        if cached_entry.modules.children ~= nil then
            for _, module in pairs(cached_entry.modules.children) do
                if module.info ~= nil then
                    modules_info[tostring(
                        maven_info:new(module.info.group_id, module.info.artifact_id, module.info.version)
                    )] =
                        true

                    if module.modules ~= nil then
                        if module.modules.children ~= nil then
                            if not validate_cached_entry_modules_checksum(module, cached_files) then
                                return false
                            end
                        else
                            return false
                        end
                    end
                else
                    return false
                end
            end
        else
            return false
        end
    else
        return true
    end

    if config.recursive_pom_search then
        for _, pom_file in ipairs(Importer.pom_files) do
            if cached_files[pom_file] ~= nil then
                if cached_files[pom_file].info ~= nil then
                    if
                        modules_info[tostring(
                            maven_info:new(
                                cached_files[pom_file].info.group_id,
                                cached_files[pom_file].info.artifact_id,
                                cached_files[pom_file].info.version
                            )
                        )] ~= nil
                    then
                        if cached_files[pom_file].checksum ~= nil then
                            if cached_files[pom_file].checksum ~= utils.file_checksum(pom_file) then
                                return false
                            end
                        else
                            return false
                        end
                    end
                end
            end
        end
    else
        for pom_file, file_info_checksum in pairs(cached_files) do
            if file_info_checksum.info ~= nil then
                if
                    modules_info[tostring(
                        maven_info:new(
                            file_info_checksum.info.group_id,
                            file_info_checksum.info.artifact_id,
                            file_info_checksum.info.version
                        )
                    )] ~= nil
                then
                    if file_info_checksum.checksum ~= nil then
                        if file_info_checksum.checksum ~= utils.file_checksum(pom_file) then
                            return false
                        else
                            Importer.pom_files:append(pom_file)
                        end
                    else
                        return false
                    end
                end
            else
                return false
            end
        end
    end

    return true
end

---@param pom_file string
---@param cached_files table<string, File_Info_Checksum|nil>
---@param cached_entries table<string, Tree_Entry|nil>
---@return Maven_Info|nil
local function get_cached_entry_info(pom_file, cached_files, cached_entries)
    if cached_files ~= nil then
        if cached_files[pom_file] ~= nil then
            if
                cached_files[pom_file].info ~= nil
                and cached_files[pom_file].checksum ~= nil
                and cached_files[pom_file].checksum == utils.file_checksum(pom_file)
            then
                local cached_entry_info = maven_info:new(
                    cached_files[pom_file].info.group_id,
                    cached_files[pom_file].info.artifact_id,
                    cached_files[pom_file].info.version
                )

                local cached_entry = cached_entries[tostring(cached_entry_info)]

                if cached_entry ~= nil then
                    if validate_cached_entry_modules_checksum(cached_entry, cached_files) then
                        return cached_entry_info
                    end
                end
            end
        end
    end
end

---@param cached_entry Tree_Entry
---@param cached_entry_info_str string
---@param required_cached_modules table<string, boolean|nil>
local function cached_entry_modules(cached_entry, cached_entry_info_str, required_cached_modules)
    if cached_entry.modules ~= nil and type(cached_entry.modules.children) == "table" then
        modules_tree[cached_entry_info_str] = {}

        for _, module in pairs(cached_entry.modules.children) do
            if module.info ~= nil then
                local module_info = maven_info:new(module.info.group_id, module.info.artifact_id, module.info.version)

                table.insert(modules_tree[cached_entry_info_str], module_info)

                required_cached_modules[tostring(module_info)] = true

                if not config.multiproject and module.children then
                    if module.modules ~= nil and module.modules.children ~= nil then
                        for _, submodule in pairs(module.modules.children) do
                            cached_entry_modules(submodule, tostring(module_info), required_cached_modules)
                        end
                    end
                end
            end
        end

        cached_entry.modules.children = {}
    end
end

local function default_idle_callback()
    task_mgr:set_on_idle_callback(function()
        task_mgr:set_on_idle_callback(function()
            task_mgr:reset()
            update_callback()
        end)

        task_mgr:reset()

        write_cache_file()
        update_callback()
    end)

    update_callback()
    process_pending()
end

---@param dir string
---@param callback fun()
function Importer.process_pom_files(dir, callback)
    reset()

    dir = utils.Path(dir).str
    cwd = dir

    if callback then
        update_callback = function()
            vim.schedule(callback)
        end
    end

    local cached_files, cached_entries = read_cache_file()

    task_mgr:set_on_idle_callback(function()
        default_idle_callback()
    end)

    Importer.pom_files = utils.find_pom_files(cwd)

    local main_project = true
    ---@type table<string, boolean|nil>
    local required_cached_modules = {}
    local files_to_process = utils.Array()

    for _, pom_file in ipairs(Importer.pom_files) do
        local cached_entry_info = get_cached_entry_info(pom_file, cached_files, cached_entries)

        if config.multiproject or main_project then
            ---@type Maven_Info|nil

            if cached_entry_info ~= nil then
                local cached_entry_info_str = tostring(cached_entry_info)
                local cached_entry = cached_entries[cached_entry_info_str]

                if cached_entry ~= nil then
                    cached_entry_modules(cached_entry, cached_entry_info_str, required_cached_modules)

                    cached_entry.info = maven_info:new(
                        cached_entry.info.group_id,
                        cached_entry.info.artifact_id,
                        cached_entry.info.version
                    )

                    Importer.Maven_Entries[cached_entry_info_str] = cached_entry
                    Importer.Pom_File_Maven_Info[pom_file] =
                        ---@diagnostic disable-next-line: need-check-nil
                        { info = cached_entry_info, checksum = cached_files[pom_file].checksum }
                    Importer.Maven_Info_Pom_File[cached_entry_info_str] = pom_file
                end
            else
                files_to_process:append({ file = pom_file, info = get_project_info(pom_file) })
            end

            main_project = false
        else
            if cached_entry_info ~= nil then
                local cached_entry_info_str = tostring(cached_entry_info)
                local cached_entry = cached_entries[cached_entry_info_str]

                if required_cached_modules[cached_entry_info_str] ~= nil and cached_entry ~= nil then
                    cached_entry.info = maven_info:new(
                        cached_entry.info.group_id,
                        cached_entry.info.artifact_id,
                        cached_entry.info.version
                    )

                    Importer.Maven_Entries[cached_entry_info_str] = cached_entry
                    Importer.Pom_File_Maven_Info[pom_file] =
                        ---@diagnostic disable-next-line: need-check-nil
                        { info = cached_entry_info, checksum = cached_files[pom_file].checksum }
                    Importer.Maven_Info_Pom_File[cached_entry_info_str] = pom_file
                end
            else
                files_to_process:append({ file = pom_file, info = get_project_info(pom_file) })
            end
        end
    end

    if files_to_process:size() == 0 then
        task_mgr:trigger_idle_callback()
    else
        for _, file_to_process in ipairs(files_to_process) do
            process_pom_file(file_to_process.file)

            if not config.multiproject then
                break
            end
        end
    end
end

---@param old_modules table<string, Tree_Entry>
local function refresh_entry_modules(old_modules)
    for info_str, module in pairs(old_modules) do
        if module.module == 0 then
            local module_pom_file = Importer.Maven_Info_Pom_File[info_str]

            if module_pom_file ~= nil then
                Importer.Maven_Info_Pom_File[info_str] = nil
                Importer.Pom_File_Maven_Info[module_pom_file] = nil
            end

            Importer.Maven_Entries[info_str] = nil
        end
    end
end

local function refresh_entry_idle_callback(old_modules)
    local function idle_callback()
        task_mgr:set_on_idle_callback(function()
            task_mgr:reset()
            update_callback()
        end)

        task_mgr:reset()

        if old_modules ~= nil then
            refresh_entry_modules(old_modules)
        end

        write_cache_file()
        update_callback()
    end

    if is_pending() then
        task_mgr:set_on_idle_callback(idle_callback)

        update_callback()
        process_pending()
    else
        idle_callback()
    end
end

---@param entry Tree_Entry
function Importer.refresh_entry(entry)
    if entry.file == nil then
        local pom_file = Importer.Maven_Info_Pom_File[tostring(entry.info)]

        if pom_file then
            ---@type table<string, Tree_Entry>
            local old_modules = {}

            if entry.modules ~= nil then
                for _, module in pairs(entry.modules.children) do
                    if not config.multiproject then
                        if module.module <= 1 then
                            old_modules[tostring(module.info)] = module
                        end
                    end

                    module.module = module.module - 1
                end
            end

            task_mgr:set_on_idle_callback(function()
                refresh_entry_idle_callback(old_modules)
            end)

            get_project_info(pom_file, entry.info)
            process_pom_file(pom_file, entry.info)
        end
    else --- Error Entry
        task_mgr:set_on_idle_callback(function()
            refresh_entry_idle_callback()
        end)

        get_project_info(entry.file, cwd)
        process_pom_file(entry.file, cwd)
    end
end

return Importer
