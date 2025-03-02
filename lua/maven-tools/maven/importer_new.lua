---@class MavenInfoNew
---@field groupId string
---@field artifactId string
---@field version string

---@class MavenDependency
---@field groupId string|nil
---@field artifactId string|nil
---@field version string|nil
---@field scope string|nil

---@class ModuleInfo
---@field path string
---@field ready boolean

---@class ProjectInfo
---@field name string
---@field info MavenInfoNew
---@field dependencies MavenInfoNew[]
---@field plugins MavenInfoNew[]
---@field modules string[]
---@field pomFile string?
---@field files table<string, string[]>
---@field testFiles table<string, string[]>
---@field sourceDirectory string?
---@field scriptSourceDirectory string?
---@field testSourceDirectory string?
---@field outputDirectory string?
---@field testOutputDirectory string?

---@class PluginInfo
---@field mavenInfo MavenInfoNew
---@field pomFile string

---@class MavenPlugin
---@field goal string
---@field commands string[]

---@class FileInfoChecksumNew
---@field info MavenInfoNew
---@field checksum string

---@class MavenImporterNew
MavenToolsImporterNew = {}

MavenToolsImporterNew.status = "Ready"

local prefix = "maven-tools."

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenToolsConfig
local mavenConfig = require(prefix .. "config.maven")

local MavenInfo = {}

---@param groupId string
---@param artifactId string
---@param version string|nil
---@return MavenInfoNew
function MavenInfo:new(groupId, artifactId, version)
    ---@type MavenInfoNew
    local res = { groupId = groupId or "", artifactId = artifactId or "", version = version or "" }

    setmetatable(res, {
        ---@param obj MavenInfoNew
        __tostring = function(obj)
            return obj.groupId .. ":" .. obj.artifactId .. ":" .. obj.version
        end,
    })

    return res
end

local MavenDependency = {}

---@param groupId string|nil
---@param artifactId string|nil
---@param version string|nil
---@param scope string|nil
---@return MavenDependency
function MavenDependency:new(groupId, artifactId, version, scope)
    ---@type MavenDependency
    local res = { groupId = groupId, artifactId = artifactId, version = version, scope = scope }

    return res
end

local xml2lua = require("maven-tools.deps.xml2lua.xml2lua")
local xmlTreeHandler = require("maven-tools.deps.xml2lua.xmlhandler.tree")

---@type Path?
local cwd

local update_callback = nil

---@type Task_Mgr
local taskMgr = utils.Task_Mgr()

---@type table<string, ProjectInfo>
MavenToolsImporterNew.mavenInfoToProjectInfoMap = {}

---@type table<string, FileInfoChecksumNew>
MavenToolsImporterNew.pomFileToMavenInfoMap = {}

---@type table<string, MavenPlugin>
MavenToolsImporterNew.pluginInfoToPluginMap = {}

---@type table<string, boolean>
MavenToolsImporterNew.pomFileIsModuleSet = {}

---@type table<string, PluginInfo>
local pendingPlugins = {}

local function set_project_entry_to_error_state(...) end

---@param pomFile Path
---@param moduleRelativePathStr string
local function get_module_abs_path(pomFile, moduleRelativePathStr)
    return pomFile:dirname():join(moduleRelativePathStr):join("pom.xml").str
end

---@param xmlPluginSubTree table
---@return MavenInfoNew
local function xml_plugin_sub_tree_to_maven_info(xmlPluginSubTree)
    return MavenInfo:new(
        xmlPluginSubTree.groupId or "org.apache.maven.plugins",
        xmlPluginSubTree.artifactId,
        xmlPluginSubTree.version
    )
end

---@param xmlProjectSubTree table
---@return MavenInfoNew[]
local function process_xml_project_sub_tree_plugins(xmlProjectSubTree)
    ---@type MavenInfoNew[]
    local plugins = {}

    if
        xmlProjectSubTree.build ~= nil
        and xmlProjectSubTree.build.plugins ~= nil
        and xmlProjectSubTree.build.plugins.plugin ~= nil
    then
        if xmlProjectSubTree.build.plugins.plugin[1] ~= nil then
            for _, plugin in pairs(xmlProjectSubTree.build.plugins.plugin) do
                local pluginInfo = xml_plugin_sub_tree_to_maven_info(plugin)
                local pluginInfoStr = tostring(pluginInfo)

                table.insert(plugins, pluginInfo)
            end
        else
            local pluginInfo = xml_plugin_sub_tree_to_maven_info(xmlProjectSubTree.build.plugins.plugin)
            local pluginInfoStr = tostring(pluginInfo)

            table.insert(plugins, pluginInfo)
        end
    end

    return plugins
end

---@param xmlProjectSubTree table
---@return MavenDependency[]
local function process_xml_project_sub_tree_dependencies(xmlProjectSubTree)
    ---@type MavenDependency[]
    local dependencies = {}

    if xmlProjectSubTree.dependencies ~= nil then
        if xmlProjectSubTree.dependencies.dependency ~= nil then
            if xmlProjectSubTree.dependencies.dependency[1] ~= nil then
                for _, dependency in pairs(xmlProjectSubTree.dependencies.dependency) do
                    local dependencyInfo = MavenDependency:new(
                        dependency.groupId,
                        dependency.artifactId,
                        dependency.version,
                        dependency.scope
                    )

                    table.insert(dependencies, dependencyInfo)
                end
            else
                local dependency = xmlProjectSubTree.dependencies.dependency
                local dependencyInfo =
                    MavenDependency:new(dependency.groupId, dependency.artifactId, dependency.version, dependency.scope)

                table.insert(dependencies, dependencyInfo)
            end
        end
    end

    return dependencies
end

---@param xmlProjectSubTree table
---@param pomFile Path?
local function process_effective_pom_project_sub_tree(xmlProjectSubTree, pomFile, refreshProjectInfo)
    if
        type(xmlProjectSubTree.groupId) ~= "string"
        or type(xmlProjectSubTree.artifactId) ~= "string"
        or type(xmlProjectSubTree.version) ~= "string"
    then
        return
    end

    local mavenInfo = MavenInfo:new(xmlProjectSubTree.groupId, xmlProjectSubTree.artifactId, xmlProjectSubTree.version)
    local mavenInfoStr = tostring(mavenInfo)

    if MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr] ~= nil then
        return --already processed
    end

    MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr] = {
        name = xmlProjectSubTree.name,
        info = mavenInfo,
        dependencies = process_xml_project_sub_tree_dependencies(xmlProjectSubTree),
        plugins = process_xml_project_sub_tree_plugins(xmlProjectSubTree),
        modules = {},
        pomFile = pomFile and pomFile.str or nil,
    }

    if pomFile ~= nil then
        MavenToolsImporterNew.pomFileToMavenInfoMap[pomFile.str] =
            { info = mavenInfo, checksum = tostring(utils.file_checksum(pomFile.str)) }
    end

    if xmlProjectSubTree.modules ~= nil and xmlProjectSubTree.modules.module ~= nil then
        if xmlProjectSubTree.modules.module[1] ~= nil then
            for _, module in pairs(xmlProjectSubTree.modules.module) do
                table.insert(MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].modules, module)
            end
        else
            table.insert(
                MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].modules,
                { path = xmlProjectSubTree.modules.module, ready = false }
            )
        end
    end

    if xmlProjectSubTree.build.sourceDirectory ~= nil then
        MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].sourceDirectory =
            utils.Path(xmlProjectSubTree.build.sourceDirectory).str
    end

    if xmlProjectSubTree.build.scriptSourceDirectory ~= nil then
        MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].scriptSourceDirectory =
            utils.Path(xmlProjectSubTree.build.scriptSourceDirectory).str
    end

    if xmlProjectSubTree.build.testSourceDirectory ~= nil then
        MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].testSourceDirectory =
            utils.Path(xmlProjectSubTree.build.testSourceDirectory).str
    end

    if xmlProjectSubTree.build.outputDirectory ~= nil then
        MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].outputDirectory =
            utils.Path(xmlProjectSubTree.build.outputDirectory).str
    end

    if xmlProjectSubTree.build.testOutputDirectory ~= nil then
        MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].testOutputDirectory =
            utils.Path(xmlProjectSubTree.build.testOutputDirectory).str
    end
end

---@param pomFile Path?
local function start_pom_file_processor_task(pomFile, refreshProjectInfo)
    MavenToolsImporterNew.status = "Processing POM files"
    print(MavenToolsImporterNew.status)

    assert(pomFile ~= nil, "")

    local pomXmlTree = xmlTreeHandler:new()
    local parser = xml2lua.parser(pomXmlTree)

    taskMgr:run(mavenConfig.importer_pipe_cmd(pomFile.str, { "help:effective-pom" }), function(xmlStr)
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
                        process_effective_pom_project_sub_tree(projectSubTree, nil, refreshProjectInfo)
                    end
                else --Single project
                    process_effective_pom_project_sub_tree(
                        pomXmlTree.root.projects.project,
                        pomFile,
                        refreshProjectInfo
                    )
                end
            elseif pomXmlTree.root.project then --Single project
                process_effective_pom_project_sub_tree(pomXmlTree.root.project, pomFile, refreshProjectInfo)
            else
                -- callback(nil)
            end
        else
            set_project_entry_to_error_state(pomFile, refreshProjectInfo, xmlStr)
            -- callback(nil)
        end
    end)
end

local function substitute_pom_variables(xml, str)
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
        return substitute_pom_variables(xml, res)
    end

    return res
end

---@param pomFile Path
local function start_resolve_maven_info_pom_file_task(pomFile, refreshProjectInfo)
    assert(pomFile ~= nil, "Invalid pom file")

    if MavenToolsImporterNew.pomFileToMavenInfoMap[pomFile.str] ~= nil then
        return -- already processed
    end

    taskMgr:readFile(pomFile.str, function(pomFileContent)
        print(pomFileContent)
        local pomXml = xmlTreeHandler:new()
        local pomParser = xml2lua.parser(pomXml)
        local success = pcall(pomParser.parse, pomParser, pomFileContent)

        if not success then
            set_project_entry_to_error_state(pomFile, refreshProjectInfo, "Failed to parse xml file")
            return
        end

        local flatXmlTree = utils.flatten_map(pomXml.root.project)

        local groupId = substitute_pom_variables(flatXmlTree, pomXml.root.project.groupId)
        local artifactId = substitute_pom_variables(flatXmlTree, pomXml.root.project.artifactId)
        local version = substitute_pom_variables(flatXmlTree, pomXml.root.project.version)

        if groupId ~= nil and artifactId ~= nil then
            local mavenInfo = MavenInfo:new(groupId, artifactId, version)
            local mavenInfoStr = tostring(mavenInfo)

            if MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr] == nil then
                return --TODO: error invalid maven info
            end

            MavenToolsImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].pomFile = pomFile.str
            MavenToolsImporterNew.pomFileToMavenInfoMap[pomFile.str] =
                { info = mavenInfo, checksum = tostring(utils.file_checksum(pomFile.str)) }
        end
    end)
end

---@param pomFile string
---@param mavenInfo MavenInfoNew
local function start_resolve_plugin_goals_task(pomFile, mavenInfo)
    local cmd = "help:describe "

    if mavenInfo.groupId ~= "" then
        cmd = cmd .. '"-DgroupId=' .. mavenInfo.groupId .. '" '
    end

    if mavenInfo.artifactId ~= "" then
        cmd = cmd .. '"-DartifactId=' .. mavenInfo.artifactId .. '" '
    end

    if mavenInfo.version ~= "" then
        cmd = cmd .. '"-Dversion=' .. mavenInfo.version .. '"'
    end

    taskMgr:run(
        mavenConfig.importer_pipe_cmd(pomFile, {
            cmd,
        }),
        function(pipeRes)
            ---@type MavenPlugin
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
                    if line:match("^" .. utils.escape_match_specials(plugin.goal) .. ":") then
                        local command = line:gsub(plugin.goal .. ":", ""):gsub("\n", "")
                        table.insert(plugin.commands, command)
                    end
                end
            end

            if plugin ~= nil then
                MavenToolsImporterNew.pluginInfoToPluginMap[tostring(mavenInfo)] = plugin
            end
        end
    )
end

local function update_modules_and_pending_plugins()
    for _, projectInfo in pairs(MavenToolsImporterNew.mavenInfoToProjectInfoMap) do
        for i, module in ipairs(projectInfo.modules) do
            if projectInfo.pomFile ~= nil then
                local modulePath = get_module_abs_path(utils.Path(projectInfo.pomFile), module)
                projectInfo.modules[i] = modulePath
                MavenToolsImporterNew.pomFileIsModuleSet[modulePath] = true
            end
        end

        for _, pluginInfo in ipairs(projectInfo.plugins) do
            local pluginInfoStr = tostring(pluginInfo)

            if pendingPlugins[pluginInfoStr] == nil and projectInfo.pomFile ~= nil then
                pendingPlugins[pluginInfoStr] = { mavenInfo = pluginInfo, pomFile = projectInfo.pomFile }
            end
        end
    end
end

local function idle_callback_init()
    MavenToolsImporterNew.status = "Resolving projects"
    print(MavenToolsImporterNew.status)

    taskMgr:set_on_idle_callback(function()
        MavenToolsImporterNew.status = "Resolving modules"
        print(MavenToolsImporterNew.status)

        update_modules_and_pending_plugins()

        MavenToolsImporterNew.status = "Resolving plugins"
        print(MavenToolsImporterNew.status)

        taskMgr:set_on_idle_callback(function()
            for pomFile, mavenInfo in pairs(MavenToolsImporterNew.pomFileToMavenInfoMap) do
                local projectFiles = {}
                local projectTestFiles = {}
                local javaFiles = utils.list_java_files(pomFile)
                local filesPrefix =
                    MavenToolsImporterNew.mavenInfoToProjectInfoMap[tostring(mavenInfo.info)].sourceDirectory
                local testFilesPrefix =
                    MavenToolsImporterNew.mavenInfoToProjectInfoMap[tostring(mavenInfo.info)].testSourceDirectory

                for _, javaFile in ipairs(javaFiles) do
                    local relativePath, count = javaFile:gsub(filesPrefix .. "/", "")

                    if count == 1 then
                        local dir, filename = relativePath:match("(.*/)([^/]*)$")

                        if dir and filename then
                            ---@cast dir string
                            ---@cast filename string

                            local package = dir:gsub("/", ".")

                            if package:match("%.$") then
                                package = package:sub(1, -2) -- remove trailing '.'
                            end

                            if projectFiles[package] == nil then
                                projectFiles[package] = {}
                            end

                            table.insert(projectFiles[package], filename)
                        end
                    else
                        relativePath, count = javaFile:gsub(testFilesPrefix .. "/", "")

                        if count == 1 then
                            local dir, filename = relativePath:match("(.*/)([^/]*)$")

                            if dir and filename then
                                ---@cast dir string
                                ---@cast filename string

                                local package = dir:gsub("/", ".")

                                if package:match("%.$") then
                                    package = package:sub(1, -2) -- remove trailing '.'
                                end

                                if projectTestFiles[package] == nil then
                                    projectTestFiles[package] = {}
                                end

                                table.insert(projectTestFiles[package], filename)
                            end
                        end
                    end
                end

                MavenToolsImporterNew.mavenInfoToProjectInfoMap[tostring(mavenInfo.info)].files = projectFiles
                MavenToolsImporterNew.mavenInfoToProjectInfoMap[tostring(mavenInfo.info)].testFiles = projectTestFiles
            end

            vim.schedule(update_callback)

            print("done!")
        end)

        local pluginTasks = 0
        for pluginInfoStr, pluginInfo in pairs(pendingPlugins) do
            if pluginInfo ~= nil then
                pluginTasks = pluginTasks + 1
                start_resolve_plugin_goals_task(pluginInfo.pomFile, pluginInfo.mavenInfo)
                pendingPlugins[pluginInfoStr] = nil
            end
        end

        taskMgr:trigger_idle_callback_if_idle()
    end)

    for _, pomFile in ipairs(MavenToolsImporterNew.pomFiles) do
        start_resolve_maven_info_pom_file_task(utils.Path(pomFile))
    end

    taskMgr:trigger_idle_callback_if_idle()
end

function MavenToolsImporterNew.update(dir, callback)
    MavenToolsImporterNew.status = "Looking of pom.xml files"
    print(MavenToolsImporterNew.status)

    update_callback = callback
    cwd = utils.Path(dir)
    assert(cwd ~= nil, "")

    MavenToolsImporterNew.pomFiles = utils.find_pom_files(cwd.str)

    taskMgr:set_on_idle_callback(idle_callback_init)

    for _, pomFile in ipairs(MavenToolsImporterNew.pomFiles) do
        start_pom_file_processor_task(utils.Path(pomFile))
    end
end

-- local str = "/home/helmy/project/pom.xml"
--
-- local pathTest = utils.Path("/home/helmy/project/pom.xml")
-- assert(pathTest, "")
-- print(pathTest:dirname().str)
-- print(pathTest:dirname():join("module/module1").str)
-- print(pathTest:dirname():join("/module/module2").str)
-- print(pathTest:dirname():join("/module/module3/").str)

return MavenToolsImporterNew
