---@class TextObj
---@field text string
---@field hl string

---@class MavenInfo
---@field groupId string
---@field artifactId string
---@field version string
---@field name string|nil

---@class TreeEntry
---@field showAlways boolean
---@field textObjs TextObj[]
---@field expanded boolean|nil
---@field children TreeEntry[]|table<string, TreeEntry>
---@field callback "0"|"1"|"2"|"3"
---@field command string|nil
---@field module integer|nil
---@field modules TreeEntry|nil
---@field info MavenInfo|nil
---@field file string|nil
---@field error integer|nil
---@field hide boolean|nil

---@class MavenProject
---@field projectInfo MavenInfo
---@field entry TreeEntry
---@field plugins MavenInfo[]
---@field modules string[]
---@field parent MavenInfo|nil

---@class FileInfoChecksum
---@field info MavenInfo|nil
---@field checksum string

---@class PendingPlugin
---@field info MavenInfo
---@field pluginInfo MavenInfo

---@class Plugin
---@field goal string
---@field commands string[]

---@class MavenImporter
MavenToolsImporter = {}

local mavenInfo = {}

local cwd

---@param groupId string
---@param artifactId string
---@param version string|nil
---@param name string|nil
---@return MavenInfo
function mavenInfo:new(groupId, artifactId, version, name)
    ---@type MavenInfo
    local res = { groupId = groupId or "", artifactId = artifactId or "", version = version or "", name = name }

    setmetatable(res, {
        ---@param obj MavenInfo
        __tostring = function(obj)
            return obj.groupId .. ":" .. obj.artifactId .. ":" .. obj.version
        end,
    })

    return res
end

local prefix = "maven-tools."

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenToolsConfig
local mavenConfig = require(prefix .. "config.maven")

local xml2lua = require("maven-tools.deps.xml2lua.xml2lua")
local xmlTreeHandler = require("maven-tools.deps.xml2lua.xmlhandler.tree")

---@type table<"lifecycle"|"plugin"|"dependency"|"repository"|"files", integer>
local projectEntryChildIndex = {
    ["lifecycle"] = 1,
    ["plugin"] = 2,
    ["dependency"] = 3,
    ["repository"] = 4,
    ["files"] = 5,
}

---@type boolean
MavenToolsImporter.busy = false

---@type table<string, TreeEntry|nil>
MavenToolsImporter.mavenEntries = {}

---@type table<string, string|nil>
MavenToolsImporter.mavenInfoPomFile = {}

---@type table<string, FileInfoChecksum|nil>
MavenToolsImporter.pomFileMavenInfo = {}

---@type table<string, string>
MavenToolsImporter.pomFileError = {}

---@type Task_Mgr
local taskMgr = utils.Task_Mgr()

---@type function
local update_callback = function(...) end

---@type table<string, TreeEntry>
local javaDirsEntries = {}

---@type Array
MavenToolsImporter.pomFiles = utils.Array()

---@type table<string, TreeEntry|"pending"|nil>
local pluginsCache = {}

---@type PendingPlugin[]
local pendingPlugins = {}

--- parent - modules
---@type table<string, MavenInfo[]|nil>
local modulesTree = {}

---@type table<string, Array|nil>
local pendingModules = {}

---@type string[]
local lifecycles = config.lifecycleCommands

---@return boolean
MavenToolsImporter.idle = function()
    return taskMgr:idle()
end

--- @return number
MavenToolsImporter.progress = function()
    return taskMgr:progress()
end

local function reset()
    MavenToolsImporter.mavenEntries = {}

    MavenToolsImporter.mavenInfoPomFile = {}

    MavenToolsImporter.pomFileMavenInfo = {}
end

---TODO: move to utils and add logic to ignore files that match config.ignoreFiles
---@param pomFile string
---@return string[]
local function list_java_files(pomFile)
    -- Extract the directory from the pom.xml path
    local pomDir = pomFile:match("(.*/)") or "./"
    local javaFiles = {}

    local function scan_directory(dir, relative_path)
        local req = vim.uv.fs_scandir(dir)
        if req then
            while true do
                local entry = vim.uv.fs_scandir_next(req)
                if not entry then
                    break
                end

                local fullPath = dir .. "/" .. entry
                local relPath = relative_path .. "/" .. entry
                local stat = vim.uv.fs_stat(fullPath)

                if stat and stat.type == "directory" then
                    -- Check if the directory contains a pom.xml file
                    local pomCheck = vim.uv.fs_stat(fullPath .. "/pom.xml")

                    if not pomCheck then
                        scan_directory(fullPath, relPath)
                    end
                elseif entry:match("%.java$") then
                    table.insert(javaFiles, relPath:sub(2)) -- Remove leading '/'
                end
            end
        end
    end

    scan_directory(pomDir, "")

    return javaFiles
end

---@param pomFile string
local function make_project_file_entry(pomFile)
    local path = pomFile:gsub("/pom.xml$", "") .. "/"

    ---@type TreeEntry
    local res = {
        showAlways = false,
        textObjs = { { text = " ", hl = "@label" }, { text = "Files", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
        module = 0,
    }

    local formattedFiles = {}
    local javaFiles = list_java_files(pomFile)

    for _, javaFile in ipairs(javaFiles) do
        local javaSubPathIndex = javaFile:find("/java/")

        if javaSubPathIndex then
            local relativePath = javaFile:sub(javaSubPathIndex + 6) -- Keep everything after /java/
            local dir, filename = relativePath:match("(.*/)([^/]*)$")

            if dir and filename then
                local key = dir:gsub("/", "."):sub(1, -2) -- Replace / with . and remove trailing .
                local test = false

                formattedFiles[key] = formattedFiles[key] or {}

                if javaSubPathIndex - 5 > 0 then
                    if javaFile:sub(javaSubPathIndex - 5, javaSubPathIndex) == "/test/" then
                        test = true
                    end
                end
                table.insert(formattedFiles[key], { filename, javaFile, test })
            end
        end
    end

    for k, v in pairs(formattedFiles) do
        ---@type TreeEntry
        local dirEntry

        if javaDirsEntries[path .. k] ~= nil then
            dirEntry = javaDirsEntries[path .. k]
        else
            dirEntry = {
                showAlways = true,
                textObjs = { { text = " ", hl = "@label" }, { text = k, hl = "@text" } },
                expanded = false,
                children = {},
                callback = "0",
                module = 0,
            }

            javaDirsEntries[path .. k] = dirEntry
        end

        dirEntry.children = {}

        for _, file in ipairs(v) do
            ---@type TreeEntry
            local fileEntry = {
                showAlways = true,
                textObjs = {
                    { text = " ", hl = "@label" },
                    { text = file[1], hl = "@text" },
                    { text = file[3] and " [test]" or "", hl = "Comment" },
                },
                expanded = false,
                children = {},
                callback = "3",
                module = 0,
                file = path .. file[2],
            }

            table.insert(dirEntry.children, fileEntry)
        end

        table.insert(res.children, dirEntry)
    end

    return res
end

---@return TreeEntry
local function lifecycle_child_entry()
    ---@type TreeEntry
    local res = {
        showAlways = false,
        textObjs = { { text = "󱂀 ", hl = "@label" }, { text = "Lifecycle", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
        module = 0,
    }

    if next(lifecycles) ~= nil then
        for i, lifecycle in ipairs(lifecycles) do
            ---@type TreeEntry
            local item = {
                showAlways = true,
                textObjs = { { text = " ", hl = "@label" }, { text = lifecycle, hl = "@text" } },
                command = lifecycle,
                expanded = false,
                children = {},
                callback = "1",
                module = 0,
            }

            res.children[i] = item
        end
    end

    return res
end

---@return TreeEntry
local function plugins_child_entry()
    ---@type TreeEntry
    local res = {
        showAlways = false,
        textObjs = { { text = "󱧽 ", hl = "@label" }, { text = "Plugins", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
    }

    return res
end

---@return TreeEntry
local function dependencies_child_entry()
    local res = {
        showAlways = false,
        textObjs = { { text = " ", hl = "@label" }, { text = "Dependencies", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
    }

    return res
end

---@return TreeEntry
local function repositories_child_entry()
    local res = {
        showAlways = false,
        textObjs = { { text = " ", hl = "@label" }, { text = "Repositories", hl = "@text" } },
        expanded = false,
        children = {},
        callback = "0",
    }

    return res
end

---@param xmlPluginSubTree table
---@return MavenInfo
local function xml_plugin_sub_tree_to_maven_info(xmlPluginSubTree)
    return mavenInfo:new(
        xmlPluginSubTree.groupId or "org.apache.maven.plugins",
        xmlPluginSubTree.artifactId,
        xmlPluginSubTree.version
    )
end

---@return TextObj[]
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

---@return TextObj[]
local function xml_repository_sub_tree_to_text_obj(xmlRepositorySubTree)
    local res = {}

    if type(xmlRepositorySubTree.id) == "string" and type(xmlRepositorySubTree.url) == "string" then
        table.insert(res, { text = xmlRepositorySubTree.id, hl = "@text" })
        table.insert(res, { text = " ", hl = "@text" })
        table.insert(res, { text = "(" .. xmlRepositorySubTree.url .. ")", hl = "Comment" })
    end

    return res
end

---@param pomFile string
---@param info MavenInfo
---@param callback fun(plugin: Plugin|nil):nil
local function process_plugin(pomFile, info, callback)
    local cmd = "help:describe "

    if info.groupId ~= "" then
        cmd = cmd .. '"-DgroupId=' .. info.groupId .. '" '
    end

    if info.artifactId ~= "" then
        cmd = cmd .. '"-DartifactId=' .. info.artifactId .. '" '
    end

    if info.version ~= "" then
        cmd = cmd .. '"-Dversion=' .. info.version .. '"'
    end

    taskMgr:run(
        mavenConfig.importer_pipe_cmd(pomFile, {
            cmd,
        }),
        function(pipeRes)
            ---@type Plugin
            local plugin = nil

            for line in pipeRes:gmatch("[^\n]*\n") do
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

---@param xmlProjectSubTree table
---@return MavenInfo[]
local function process_xml_project_sub_tree_plugins(xmlProjectSubTree)
    ---@type MavenInfo[]
    local plugins = {}

    if
        xmlProjectSubTree.build ~= nil
        and xmlProjectSubTree.build.plugins ~= nil
        and xmlProjectSubTree.build.plugins.plugin ~= nil
    then
        if xmlProjectSubTree.build.plugins.plugin[1] ~= nil then
            for _, plugin in pairs(xmlProjectSubTree.build.plugins.plugin) do
                table.insert(plugins, xml_plugin_sub_tree_to_maven_info(plugin))
            end
        else
            table.insert(plugins, xml_plugin_sub_tree_to_maven_info(xmlProjectSubTree.build.plugins.plugin))
        end
    end

    return plugins
end

---@param xmlProjectSubTree table
---@param projectEntry TreeEntry
local function process_xml_project_sub_tree_dependencies(xmlProjectSubTree, projectEntry)
    if xmlProjectSubTree.dependencies ~= nil and xmlProjectSubTree.dependencies.dependency ~= nil then
        if xmlProjectSubTree.dependencies.dependency[1] ~= nil then
            for _, dependency in pairs(xmlProjectSubTree.dependencies.dependency) do
                local dep = extract_dependency(dependency)

                if dep[1] ~= nil then
                    ---@type TreeEntry
                    local depEntry = {
                        showAlways = true,
                        textObjs = { { text = " ", hl = "@label" } },
                        expanded = false,
                        children = {},
                        callback = "2",
                        module = 0,
                    }

                    depEntry.textObjs = utils.array_join(depEntry.textObjs, dep)

                    table.insert(projectEntry.children[3].children, depEntry)
                end
            end
        else
            local dep = extract_dependency(xmlProjectSubTree.dependencies.dependency)

            if dep[1] ~= nil then
                ---@type TreeEntry
                local depEntry = {
                    showAlways = true,
                    textObjs = { { text = " ", hl = "@label" } },
                    expanded = false,
                    children = {},
                    callback = "2",
                    module = 0,
                }

                depEntry.textObjs = utils.array_join(depEntry.textObjs, dep)

                table.insert(projectEntry.children[3].children, depEntry)
            end
        end
    end
end

---@param project table
---@param entry TreeEntry
local function process_xml_project_sub_tree_repositories(project, entry)
    if project.repositories ~= nil and project.repositories.repository ~= nil then
        if project.repositories.repository[1] ~= nil then
            for _, repository in pairs(project.repositories.repository) do
                local repo = xml_repository_sub_tree_to_text_obj(repository)

                if repo[1] ~= nil then
                    ---@type TreeEntry
                    local repoEntry = {
                        showAlways = true,
                        textObjs = { { text = "󰳐 ", hl = "@label" } },
                        callback = "2",
                        expanded = false,
                        children = {},
                        module = 0,
                    }

                    repoEntry.textObjs = utils.array_join(repoEntry.textObjs, repo)

                    table.insert(entry.children[4].children, repoEntry)
                end
            end
        else
            local repo = xml_repository_sub_tree_to_text_obj(project.repositories.repository)

            if repo[1] ~= nil then
                ---@type TreeEntry
                local repoEntry = {
                    showAlways = true,
                    textObjs = { { text = "󰳐 ", hl = "@label" } },
                    callback = "2",
                    expanded = false,
                    children = {},
                    module = 0,
                }

                repoEntry.textObjs = utils.array_join(repoEntry.textObjs, repo)

                table.insert(entry.children[4].children, repoEntry)
            end
        end
    end
end

---@param xmlProjectSubTree table
---@param entry TreeEntry
---@return string[]
local function process_xml_project_sub_tree_modules(xmlProjectSubTree, entry)
    ---@type string[]
    local modules = {}

    if xmlProjectSubTree.modules ~= nil and xmlProjectSubTree.modules.module ~= nil then
        entry.modules = {
            showAlways = true,
            textObjs = { { text = "󱧷 ", hl = "@label" }, { text = "Modules", hl = "@text" } },
            expanded = false,
            children = {},
            callback = "0",
            module = 0,
        }

        if xmlProjectSubTree.modules.module[1] ~= nil then
            for _, module in pairs(xmlProjectSubTree.modules.module) do
                table.insert(modules, module)
            end
        else
            table.insert(modules, xmlProjectSubTree.modules.module)
        end
    end

    return modules
end

---@param pom_file string
---@param refreshProjectInfo MavenInfo|nil
---@param error string
local function set_project_entry_to_error_state(pom_file, refreshProjectInfo, error)
    if refreshProjectInfo ~= nil then
        MavenToolsImporter.pomFileMavenInfo[pom_file] = nil
        MavenToolsImporter.mavenInfoPomFile[tostring(refreshProjectInfo)] = nil

        --Remove entry from projects that have it as a module
        if MavenToolsImporter.mavenEntries[tostring(refreshProjectInfo)].module > 0 then
            for k, v in pairs(MavenToolsImporter.mavenEntries) do
                if v.modules ~= nil then
                    for moduleInfo, module in pairs(v.modules.children) do
                        print("moduleInfo=", tostring(moduleInfo), "refreshProjectInfo=", tostring(refreshProjectInfo))
                        if tostring(moduleInfo) == tostring(refreshProjectInfo) then
                            --TODO: set child to a value that can be used to reinsert the module once the error is resolved.
                            v.modules.children[moduleInfo] = nil
                        end
                    end
                end
            end
        end

        MavenToolsImporter.mavenEntries[tostring(refreshProjectInfo)] = nil
    end

    local dir = cwd:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

    if dir:sub(#dir, #dir) ~= "/" then
        dir = dir .. "/"
    end

    local relativePath = pom_file:gsub(dir, "")

    MavenToolsImporter.mavenEntries[pom_file] = {
        showAlways = true,
        textObjs = {
            { text = " ", hl = "@label" },
            { text = "error", hl = "DiagnosticUnderlineError" },
            { text = " ", hl = "@text" },
            {
                text = "(" .. relativePath .. ")",
                hl = "Comment",
            },
        },
        expanded = false,
        callback = "0",
        children = {},
        module = 0,
        file = pom_file,
    }

    MavenToolsImporter.pomFileError[pom_file] = error
end

--TODO: move to utils
---@param tbl table
---@return table
local function linearize_table(tbl)
    local result = {}

    local function traverse(subtable, currentKey)
        for key, value in pairs(subtable) do
            local newKey = ""

            if currentKey == "" then
                newKey = key
            else
                newKey = currentKey .. "." .. key
            end

            if type(value) == "table" then
                traverse(value, newKey)
            else
                result[newKey] = value
            end
        end
    end

    traverse(tbl, "")

    return result
end

--TODO: rename and move to utils
---@param xml any
---@param str string
---@return string|nil
local function substitute(xml, str)
    if xml == nil or str == nil then
        return nil
    end

    local res = str

    for var in str:gmatch("%${(.-)}") do
        local value = xml[var:gsub("project.", "")]

        if value == nil then
            value = xml["properties." .. var:gsub("project%.", "")]
        end

        res = res:gsub("%${" .. var .. "}", value or var)
    end

    if res:match("%${.-}") then
        return substitute(xml, res)
    end

    return res
end

---@param pomFile string
---@param refreshProjectInfo MavenInfo|nil
---@return MavenInfo|nil
local function update_project(pomFile, refreshProjectInfo)
    local pomFileHandle = io.open(pomFile, "r")
    local projectInfo = nil

    if pomFileHandle ~= nil then
        local pom_file_str = pomFileHandle:read("*a")
        pomFileHandle:close()

        local pomXml = xmlTreeHandler:new()
        local pomParser = xml2lua.parser(pomXml)
        local success = pcall(pomParser.parse, pomParser, pom_file_str)
        -- pomParser:parse(pom_file_str)

        if not success then
            set_project_entry_to_error_state(pomFile, refreshProjectInfo, "Failed to parse xml file")
            return nil
        end

        local linearXml = linearize_table(pomXml.root.project)

        if refreshProjectInfo then
            for k, v in pairs(linearXml) do
                print(k, v)
            end
        end

        local groupId = substitute(linearXml, pomXml.root.project.groupId)
        local artifactId = substitute(linearXml, pomXml.root.project.artifactId)
        local version = substitute(linearXml, pomXml.root.project.version)
        local name = substitute(linearXml, pomXml.root.project.name)

        if groupId ~= nil and artifactId ~= nil then
            projectInfo = mavenInfo:new(groupId, artifactId, version, name)

            MavenToolsImporter.mavenInfoPomFile[tostring(projectInfo)] = pomFile
            MavenToolsImporter.pomFileMavenInfo[pomFile] =
                { info = projectInfo, checksum = tostring(utils.file_checksum(pomFile)) }

            if refreshProjectInfo ~= nil and tostring(refreshProjectInfo) ~= tostring(projectInfo) then
                MavenToolsImporter.mavenInfoPomFile[tostring(refreshProjectInfo)] = nil
                MavenToolsImporter.mavenEntries[tostring(refreshProjectInfo)] = nil
            end
        end
    end

    return projectInfo
end

---@param xmlProjectSubTree table
---@param refreshProjectInfo MavenInfo|nil
---@return MavenProject|nil
local function process_xml_project_sub_tree(xmlProjectSubTree, refreshProjectInfo)
    ---@type TreeEntry
    local projectEntry = {
        showAlways = true,
        textObjs = { { text = " ", hl = "@label" } },
        expanded = false,
        callback = "0",
        children = {},
        modules = nil,
        module = 0,
    }

    projectEntry.children[projectEntryChildIndex["lifecycle"]] = lifecycle_child_entry()
    projectEntry.children[projectEntryChildIndex["plugin"]] = plugins_child_entry()
    projectEntry.children[projectEntryChildIndex["dependency"]] = dependencies_child_entry()
    projectEntry.children[projectEntryChildIndex["repository"]] = repositories_child_entry()

    if refreshProjectInfo ~= nil then
        if MavenToolsImporter.mavenEntries[tostring(refreshProjectInfo)] then
            projectEntry.module = MavenToolsImporter.mavenEntries[tostring(refreshProjectInfo)].module
        end
    end

    if
        type(xmlProjectSubTree.groupId) == "string"
        and type(xmlProjectSubTree.artifactId) == "string"
        and type(xmlProjectSubTree.version) == "string"
    then
        local projectInfo =
            mavenInfo:new(xmlProjectSubTree.groupId, xmlProjectSubTree.artifactId, xmlProjectSubTree.version)

        if MavenToolsImporter.mavenEntries[tostring(projectInfo)] ~= nil and refreshProjectInfo == nil then
            return nil
        end

        projectEntry.info = projectInfo

        if refreshProjectInfo then
            print(
                "project info:",
                xmlProjectSubTree.artifactId,
                xmlProjectSubTree.groupId,
                xmlProjectSubTree.artifactId
            )
            print("maven info pom file:", MavenToolsImporter.mavenInfoPomFile[tostring(projectInfo)])
            print(
                "pom file maven info:",
                MavenToolsImporter.pomFileMavenInfo[MavenToolsImporter.mavenInfoPomFile[tostring(projectInfo)]]
            )
            print(
                "pom file maven info info:",
                MavenToolsImporter.pomFileMavenInfo[MavenToolsImporter.mavenInfoPomFile[tostring(projectInfo)]].info
            )
            print(
                "pom file maven info info name:",
                MavenToolsImporter.pomFileMavenInfo[MavenToolsImporter.mavenInfoPomFile[tostring(projectInfo)]].info.name
            )
            print("project artifactId", xmlProjectSubTree.artifactId)
        end

        --TODO: investigate info begin null when refreshing an errored entry
        table.insert(projectEntry.textObjs, {
            text = MavenToolsImporter.pomFileMavenInfo[MavenToolsImporter.mavenInfoPomFile[tostring(projectInfo)]].info.name
                or xmlProjectSubTree.artifactId,
            hl = "@text",
        })

        ---@type MavenInfo|nil
        local parent = nil

        if
            xmlProjectSubTree.parent ~= nil
            and xmlProjectSubTree.parent.groupId ~= nil
            and xmlProjectSubTree.parent.artifactId ~= nil
            and xmlProjectSubTree.parent.version ~= nil
        then
            parent = mavenInfo:new(
                xmlProjectSubTree.parent.groupId,
                xmlProjectSubTree.parent.artifactId,
                xmlProjectSubTree.parent.version
            )
        end

        local plugins = process_xml_project_sub_tree_plugins(xmlProjectSubTree)
        local modules = process_xml_project_sub_tree_modules(xmlProjectSubTree, projectEntry)
        process_xml_project_sub_tree_dependencies(xmlProjectSubTree, projectEntry)
        process_xml_project_sub_tree_repositories(xmlProjectSubTree, projectEntry)

        return {
            projectInfo = projectInfo,
            entry = projectEntry,
            plugins = plugins,
            modules = modules,
            parent = parent,
        }
    end
end

---@param entry TreeEntry
---@param callback fun(effective_pom:string):nil
function MavenToolsImporter.effective_pom(entry, callback)
    local pomFile = ""

    if entry.file ~= nil then
        pomFile = entry.file
    else
        pomFile = MavenToolsImporter.mavenInfoPomFile[tostring(entry.info)]
    end

    if pomFile == nil then
        return
    end

    taskMgr:run(mavenConfig.importer_pipe_cmd(pomFile, { "help:effective-pom" }), function(xml)
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

            vim.schedule(function()
                callback(xml:sub(start, finish))
            end)
        end
    end)
end

---@param pomFile string
---@param refreshProjectInfo MavenInfo|nil
---@param callback fun(maven_project: MavenProject|nil)
local function process_pom_file_task(pomFile, refreshProjectInfo, callback)
    local pomXmlTree = xmlTreeHandler:new()
    local parser = xml2lua.parser(pomXmlTree)

    taskMgr:run(mavenConfig.importer_pipe_cmd(pomFile, { "help:effective-pom" }), function(xmlStr)
        local start = xmlStr:find("<projects")

        ---@type integer|nil
        local finish = nil

        ---@type string
        local finishTag = nil

        if start ~= nil then
            finishTag = "</projects>"
        else
            start = xmlStr:find("<project")

            finishTag = "</project>"
        end

        finish = xmlStr:find(finishTag)

        if start ~= nil and finish ~= nil then
            finish = finish + #finishTag
            local projectXml = xmlStr:sub(start, finish)

            parser:parse(projectXml)

            if pomXmlTree.root.projects ~= nil and pomXmlTree.root.projects.project ~= nil then
                if pomXmlTree.root.projects.project[1] ~= nil then --Multiple projects
                    for _, projectSubTree in pairs(pomXmlTree.root.projects.project) do
                        callback(process_xml_project_sub_tree(projectSubTree, refreshProjectInfo))
                    end
                else --Single project
                    callback(process_xml_project_sub_tree(pomXmlTree.root.projects.project, refreshProjectInfo))
                end
            elseif pomXmlTree.root.project then --Single project
                callback(process_xml_project_sub_tree(pomXmlTree.root.project, refreshProjectInfo))
            else
                callback(nil)
            end
        else
            set_project_entry_to_error_state(pomFile, refreshProjectInfo, xmlStr)
            callback(nil)
        end
    end)
end

local function process_pending_plugins()
    ---@type table<string, fun()[]|nil>
    local processPluginAssignments = {}

    local processPluginsQueue = utils.Queue()

    for _, pendingPlugin in ipairs(pendingPlugins) do
        local pluginId = tostring(pendingPlugin.pluginInfo)

        if processPluginAssignments[pluginId] == nil then
            processPluginAssignments[pluginId] = {}
        end

        if pluginsCache[pluginId] == nil then
            pluginsCache[pluginId] = "pending"

            processPluginsQueue:push({
                MavenToolsImporter.mavenInfoPomFile[tostring(pendingPlugin.info)],
                pendingPlugin.pluginInfo,
                function(callbackRes)
                    if callbackRes == nil then
                        return
                    end

                    ---@type TreeEntry
                    local pluginEntry = {
                        showAlways = true,
                        textObjs = { { text = " ", hl = "@label" }, { text = callbackRes.goal, hl = "@text" } },
                        expanded = false,
                        children = {},
                        callback = "0",
                        module = 0,
                    }

                    for _, command in ipairs(callbackRes.commands) do
                        ---@type TreeEntry
                        local pluginCommandEntry = {
                            showAlways = true,
                            textObjs = { { text = " ", hl = "@label" }, { text = command[1], hl = "@text" } },
                            command = callbackRes.goal .. ":" .. command[1],
                            expanded = false,
                            children = {},
                            callback = "1",
                            module = 0,
                        }

                        table.insert(pluginEntry.children, pluginCommandEntry)
                    end

                    pluginsCache[pluginId] = pluginEntry

                    table.insert(
                        MavenToolsImporter.mavenEntries[tostring(pendingPlugin.info)].children[2].children,
                        utils.deepcopy(pluginEntry)
                    )

                    if processPluginAssignments[pluginId] ~= nil then
                        for _, pending_callback in ipairs(processPluginAssignments[pluginId]) do
                            pending_callback()
                        end
                    end

                    update_callback()
                end,
            })
        else
            table.insert(processPluginAssignments[pluginId], function()
                table.insert(
                    MavenToolsImporter.mavenEntries[tostring(pendingPlugin.info)].children[2].children,
                    utils.deepcopy(pluginsCache[pluginId])
                )
            end)
        end
    end

    local task = processPluginsQueue:pop()

    if task == nil then
        for _, pendingCallbacks in pairs(processPluginAssignments) do
            for _, pending_callback in ipairs(pendingCallbacks) do
                pending_callback()
            end
        end
    end

    while task ~= nil do
        process_plugin(task[1], task[2], task[3])

        task = processPluginsQueue:pop()
    end
end

local function process_pending_modules_tree()
    for parent, modules in pairs(modulesTree) do
        local parentEntry = MavenToolsImporter.mavenEntries[parent]

        if parentEntry ~= nil then
            for _, module in ipairs(modules) do
                local moduleEntry = MavenToolsImporter.mavenEntries[tostring(module)]
                local moduleFile = MavenToolsImporter.mavenInfoPomFile[tostring(module)]

                if moduleEntry ~= nil and moduleFile ~= nil then
                    if pendingModules[moduleFile] ~= nil then
                        pendingModules[moduleFile]:remove_value(parent)
                    end

                    if parentEntry.modules ~= nil then
                        moduleEntry.module = moduleEntry.module + 1

                        parentEntry.modules.children[tostring(module)] = moduleEntry
                    end
                end
            end
        end
    end
end

local function process_pending_modules()
    for moduleFile, parents in pairs(pendingModules) do
        if parents:size() > 0 then
            local moduleInfo = nil

            if MavenToolsImporter.pomFileMavenInfo[moduleFile] ~= nil then
                moduleInfo = MavenToolsImporter.pomFileMavenInfo[moduleFile].info
            else
                moduleInfo = update_project(moduleFile)
            end

            if moduleInfo ~= nil then
                local moduleEntry = MavenToolsImporter.mavenEntries[tostring(moduleInfo)]

                if moduleEntry ~= nil then
                    for _, parent in ipairs(parents) do
                        moduleEntry.module = moduleEntry.module + 1

                        MavenToolsImporter.mavenEntries[parent].modules.children[tostring(moduleInfo)] = moduleEntry
                    end
                end
            end
        end
    end
end

---@return boolean
local function is_pending()
    for _, _ in ipairs(pendingPlugins) do
        return true
    end

    for _, _ in ipairs(modulesTree) do
        return true
    end

    for _, _ in ipairs(pendingModules) do
        return true
    end

    return false
end

local function process_pending()
    process_pending_plugins()
    pendingPlugins = {}

    process_pending_modules_tree()
    modulesTree = {}

    update_callback()

    process_pending_modules()

    pendingModules = {}

    if taskMgr:idle() then
        taskMgr:trigger_idle_callback()
    end
end

---@param pomFile string
---@param refreshProjectInfo MavenInfo|nil
local function process_pom_file(pomFile, refreshProjectInfo)
    local fileInfo = MavenToolsImporter.pomFileMavenInfo[pomFile]

    ---@type MavenInfo|nil
    local projectInfo = nil

    if fileInfo ~= nil then
        projectInfo = fileInfo.info
    end

    if projectInfo ~= nil then
        if MavenToolsImporter.mavenEntries[tostring(projectInfo)] ~= nil and refreshProjectInfo == nil then
            --File is already processed
            return nil
        end

        process_pom_file_task(pomFile, refreshProjectInfo, function(mavenProject)
            if mavenProject ~= nil then
                MavenToolsImporter.mavenEntries[tostring(mavenProject.projectInfo)] = mavenProject.entry

                for _, info in ipairs(mavenProject.plugins) do
                    ---@type PendingPlugin
                    local pendingPlugin = { info = mavenProject.projectInfo, pluginInfo = info }

                    table.insert(pendingPlugins, pendingPlugin)
                end

                for _, module in ipairs(mavenProject.modules) do
                    local moduleFile = utils
                        .Path(MavenToolsImporter.mavenInfoPomFile[tostring(mavenProject.projectInfo)])
                        :dirname()
                        :join(module)
                        :join("pom.xml").str

                    if pendingModules[moduleFile] == nil then
                        pendingModules[moduleFile] = utils.Array()
                    end

                    pendingModules[moduleFile]:append(tostring(mavenProject.projectInfo))
                end

                if mavenProject.parent ~= nil then
                    local parentId = tostring(mavenProject.parent)

                    if modulesTree[parentId] == nil then
                        modulesTree[parentId] = { mavenProject.projectInfo }
                    else
                        table.insert(modulesTree[parentId], mavenProject.projectInfo)
                    end
                end
            end

            update_callback()
        end)
    end
end

---@return table<string, FileInfoChecksum|nil>
---@return table<string, TreeEntry|nil>
local function read_cache_file()
    local neovimConfigPath = vim.fn.stdpath("config")

    if type(neovimConfigPath) == "table" then
        neovimConfigPath = neovimConfigPath[1]
    end

    local resFile = io.open(utils.Path(neovimConfigPath):join(".maven").str .. "/plugins.cache.json", "r")

    if resFile then
        local res_str = resFile:read("*a")
        resFile:close()

        pluginsCache = vim.fn.json_decode(res_str)
    end

    ---@type table<string, FileInfoChecksum|nil>
    local cachedFiles

    ---@type table<string, TreeEntry|nil>
    local cachedEntries

    resFile = io.open(utils.Path(cwd):join(config.localConfigDir):join("cache.json").str, "r")

    if resFile then
        local resStr = resFile:read("*a")
        resFile:close()
        local cache = vim.fn.json_decode(resStr)

        if
            cache.version ~= nil
            and cache.checksum ~= nil
            and cache.version == config.version
            and cache.checksum == mavenConfig.importer_checksum()
        then
            cachedFiles = cache.files
            cachedEntries = cache.entries
        end
    end

    return cachedFiles, cachedEntries
end

local function write_plugins_cache_file()
    local configPath = vim.fn.stdpath("config")

    if type(configPath) == "table" then
        configPath = configPath[1]
    end

    local path = utils.Path(configPath):join(".maven").str
    local success, _ = utils.create_directories(path)

    if success then
        local resFile = io.open(path .. "/plugins.cache.json", "r")

        if resFile then
            vim.schedule(function()
                local globalPluginsCache = vim.fn.json_decode(resFile:read("*a"))
                resFile:close()

                pluginsCache = utils.table_join(globalPluginsCache, pluginsCache)

                resFile = io.open(path .. "/plugins.cache.json", "w")

                if resFile then
                    resFile:write(vim.fn.json_encode(pluginsCache))
                    resFile:close()
                end
            end)
        else
            vim.schedule(function()
                resFile = io.open(path .. "/plugins.cache.json", "w")

                if resFile then
                    resFile:write(vim.fn.json_encode(pluginsCache))
                    resFile:close()
                end
            end)
        end
    end
end

local function write_cache_file()
    if config.cacheEntries == false then
        return
    end

    local path = utils.Path(cwd):join(config.localConfigDir).str
    local success, _ = utils.create_directories(path)

    if success then
        local resFile = io.open(path .. "/cache.json", "w")

        if resFile then
            vim.schedule(function()
                resFile:write(vim.fn.json_encode({
                    version = config.version,
                    checksum = mavenConfig.importer_checksum(),
                    files = MavenToolsImporter.pomFileMavenInfo,
                    entries = MavenToolsImporter.mavenEntries,
                }))

                resFile:close()
            end)
        end
    end

    write_plugins_cache_file()
end

---@param cachedEntry TreeEntry
---@param cachedFiles table<string, FileInfoChecksum|nil>
---@return boolean
local function validate_cached_entry_modules_checksum(cachedEntry, cachedFiles)
    ---@type table<string, boolean|nil>
    local modulesInfo = {}

    if cachedEntry.modules ~= nil then
        if cachedEntry.modules.children ~= nil then
            for _, module in pairs(cachedEntry.modules.children) do
                if module.info ~= nil then
                    modulesInfo[tostring(
                        mavenInfo:new(module.info.groupId, module.info.artifactId, module.info.version)
                    )] =
                        true

                    if module.modules ~= nil then
                        if module.modules.children ~= nil then
                            if not validate_cached_entry_modules_checksum(module, cachedFiles) then
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

    if config.recursivePomSearch then
        for _, pomFile in ipairs(MavenToolsImporter.pomFiles) do
            if cachedFiles[pomFile] ~= nil then
                if cachedFiles[pomFile].info ~= nil then
                    if
                        modulesInfo[tostring(
                            mavenInfo:new(
                                cachedFiles[pomFile].info.groupId,
                                cachedFiles[pomFile].info.artifactId,
                                cachedFiles[pomFile].info.version
                            )
                        )] ~= nil
                    then
                        if cachedFiles[pomFile].checksum ~= nil then
                            if cachedFiles[pomFile].checksum ~= utils.file_checksum(pomFile) then
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
        for pomFile, fileInfoChecksum in pairs(cachedFiles) do
            if fileInfoChecksum.info ~= nil then
                if
                    modulesInfo[tostring(
                        mavenInfo:new(
                            fileInfoChecksum.info.groupId,
                            fileInfoChecksum.info.artifactId,
                            fileInfoChecksum.info.version
                        )
                    )] ~= nil
                then
                    if fileInfoChecksum.checksum ~= nil then
                        if fileInfoChecksum.checksum ~= utils.file_checksum(pomFile) then
                            return false
                        else
                            MavenToolsImporter.pomFiles:append(pomFile)
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

---@param pomFile string
---@param cachedFiles table<string, FileInfoChecksum|nil>
---@param cachedEntries table<string, TreeEntry|nil>
---@return MavenInfo|nil
local function get_cached_entry_info(pomFile, cachedFiles, cachedEntries)
    if cachedFiles ~= nil then
        if cachedFiles[pomFile] ~= nil then
            if
                cachedFiles[pomFile].info ~= nil
                and cachedFiles[pomFile].checksum ~= nil
                and cachedFiles[pomFile].checksum == utils.file_checksum(pomFile)
            then
                local cached_entry_info = mavenInfo:new(
                    cachedFiles[pomFile].info.groupId,
                    cachedFiles[pomFile].info.artifactId,
                    cachedFiles[pomFile].info.version
                )

                local cachedEntry = cachedEntries[tostring(cached_entry_info)]

                if cachedEntry ~= nil then
                    if validate_cached_entry_modules_checksum(cachedEntry, cachedFiles) then
                        return cached_entry_info
                    end
                end
            end
        end
    end
end

---@param cachedEntry TreeEntry
---@param cachedEntryInfoStr string
---@param requiredCachedModules table<string, boolean|nil>
local function cached_entry_modules(cachedEntry, cachedEntryInfoStr, requiredCachedModules)
    if cachedEntry.modules ~= nil and type(cachedEntry.modules.children) == "table" then
        modulesTree[cachedEntryInfoStr] = {}

        for _, module in pairs(cachedEntry.modules.children) do
            if module.info ~= nil then
                local moduleInfo = mavenInfo:new(module.info.groupId, module.info.artifactId, module.info.version)

                table.insert(modulesTree[cachedEntryInfoStr], moduleInfo)

                requiredCachedModules[tostring(moduleInfo)] = true

                if not config.multiproject and module.children then
                    if module.modules ~= nil and module.modules.children ~= nil then
                        for _, submodule in pairs(module.modules.children) do
                            cached_entry_modules(submodule, tostring(moduleInfo), requiredCachedModules)
                        end
                    end
                end
            end
        end

        cachedEntry.modules.children = {}
    end
end

function MavenToolsImporter.update_projects_files()
    for _, entry in pairs(MavenToolsImporter.mavenEntries) do
        ---@cast entry TreeEntry
        if entry.info ~= nil then
            local pomFile = MavenToolsImporter.mavenInfoPomFile[tostring(entry.info)]

            if pomFile ~= nil then
                local expand = false

                if entry.children[5] ~= nil then
                    expand = entry.children[5].expanded
                end

                entry.children[5] = make_project_file_entry(pomFile)
                entry.children[5].expanded = expand
            end
        end
    end
end

local function last_idle_callback()
    taskMgr:reset()
    MavenToolsImporter.update_projects_files()
    update_callback()
    MavenToolsImporter.busy = false
end

local function default_idle_callback()
    taskMgr:set_on_idle_callback(function()
        taskMgr:set_on_idle_callback(last_idle_callback)

        taskMgr:reset()

        write_cache_file()
        update_callback()
    end)

    MavenToolsImporter.update_projects_files()
    update_callback()
    process_pending()
end

---@param dir string
---@param callback fun()
function MavenToolsImporter.process_pom_files(dir, callback)
    if MavenToolsImporter.busy then
        return
    end

    MavenToolsImporter.busy = true

    reset()

    dir = utils.Path(dir).str
    cwd = dir

    if callback then
        update_callback = function()
            vim.schedule(callback)
        end
    end

    local cachedFiles, cachedEntries = read_cache_file()

    taskMgr:set_on_idle_callback(default_idle_callback)

    MavenToolsImporter.pomFiles = utils.find_pom_files(cwd)

    local mainProject = true

    ---@type table<string, boolean|nil>
    local requiredCachedModules = {}

    local filesToProcess = utils.Array()

    for _, pomFile in ipairs(MavenToolsImporter.pomFiles) do
        local cachedIntryInfo = get_cached_entry_info(pomFile, cachedFiles, cachedEntries)

        if config.multiproject or mainProject then
            ---@type MavenInfo|nil

            if cachedIntryInfo ~= nil then
                local cachedEntryInfoStr = tostring(cachedIntryInfo)
                local cachedEntry = cachedEntries[cachedEntryInfoStr]

                if cachedEntry ~= nil then
                    cached_entry_modules(cachedEntry, cachedEntryInfoStr, requiredCachedModules)

                    cachedEntry.info =
                        mavenInfo:new(cachedEntry.info.groupId, cachedEntry.info.artifactId, cachedEntry.info.version)

                    MavenToolsImporter.mavenEntries[cachedEntryInfoStr] = cachedEntry
                    MavenToolsImporter.mavenEntries[cachedEntryInfoStr].children[1] = lifecycle_child_entry()
                    MavenToolsImporter.pomFileMavenInfo[pomFile] =
                        { info = cachedIntryInfo, checksum = cachedFiles[pomFile].checksum }
                    MavenToolsImporter.mavenInfoPomFile[cachedEntryInfoStr] = pomFile
                end
            else
                filesToProcess:append({ file = pomFile, info = update_project(pomFile) })
            end

            mainProject = false
        else
            if cachedIntryInfo ~= nil then
                local cachedEntryInfoStr = tostring(cachedIntryInfo)
                local cachedEntry = cachedEntries[cachedEntryInfoStr]

                if requiredCachedModules[cachedEntryInfoStr] ~= nil and cachedEntry ~= nil then
                    cachedEntry.info =
                        mavenInfo:new(cachedEntry.info.groupId, cachedEntry.info.artifactId, cachedEntry.info.version)

                    MavenToolsImporter.mavenEntries[cachedEntryInfoStr] = cachedEntry
                    MavenToolsImporter.pomFileMavenInfo[pomFile] =
                        { info = cachedIntryInfo, checksum = cachedFiles[pomFile].checksum }
                    MavenToolsImporter.mavenInfoPomFile[cachedEntryInfoStr] = pomFile
                end
            else
                filesToProcess:append({ file = pomFile, info = update_project(pomFile) })
            end
        end
    end

    if filesToProcess:size() == 0 then
        taskMgr:trigger_idle_callback()
    else
        for _, fileToProcess in ipairs(filesToProcess) do
            process_pom_file(fileToProcess.file)

            if not config.multiproject then
                break
            end
        end
    end
end

---@param oldModules table<string, TreeEntry>
local function refresh_entry_modules(oldModules)
    for infoStr, module in pairs(oldModules) do
        if module.module == 0 then
            local modulePomFile = MavenToolsImporter.mavenInfoPomFile[infoStr]

            if modulePomFile ~= nil then
                MavenToolsImporter.mavenInfoPomFile[infoStr] = nil
                MavenToolsImporter.pomFileMavenInfo[modulePomFile] = nil
            end

            MavenToolsImporter.mavenEntries[infoStr] = nil
        end
    end
end

local function refresh_entry_idle_callback(oldModules)
    local function idle_callback()
        taskMgr:set_on_idle_callback(last_idle_callback)

        taskMgr:reset()

        if oldModules ~= nil then
            refresh_entry_modules(oldModules)
        end

        write_cache_file()
        update_callback()
    end

    if is_pending() then
        taskMgr:set_on_idle_callback(idle_callback)

        update_callback()
        process_pending()
    else
        idle_callback()
    end
end

---@param entry TreeEntry
function MavenToolsImporter.refresh_entry(entry)
    MavenToolsImporter.busy = true

    if entry.file == nil then
        local pomFile = MavenToolsImporter.mavenInfoPomFile[tostring(entry.info)]

        if pomFile then
            ---@type table<string, TreeEntry>
            local oldModules = {}

            if entry.modules ~= nil then
                for _, module in pairs(entry.modules.children) do
                    if not config.multiproject then
                        if module.module <= 1 then
                            oldModules[tostring(module.info)] = module
                        end
                    end

                    module.module = module.module - 1
                end
            end

            taskMgr:set_on_idle_callback(function()
                refresh_entry_idle_callback(oldModules)
            end)

            update_project(pomFile, entry.info)
            process_pom_file(pomFile, entry.info)
        end
    else --- Error Entry
        taskMgr:set_on_idle_callback(function()
            refresh_entry_idle_callback()
        end)

        update_project(entry.file, cwd)
        process_pom_file(entry.file, cwd)
    end
end

return MavenToolsImporter
