---@class MavenInfo
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

---@class ProjectFile
---@field path string
---@field filename string

---@class ProjectInfo
---@field name string
---@field info MavenInfo
---@field dependencies MavenDependency[]
---@field plugins MavenInfo[]
---@field modules string[]
---@field pomFile string?
---@field files table<string, ProjectFile[]>
---@field testFiles table<string, ProjectFile[]>
---@field sourceDirectory string?
---@field scriptSourceDirectory string?
---@field testSourceDirectory string?
---@field outputDirectory string?
---@field testOutputDirectory string?

---@class PluginInfo
---@field mavenInfo MavenInfo
---@field pomFile string

---@class MavenPlugin
---@field goal string
---@field commands string[]

---@class FileInfoChecksum
---@field info MavenInfo
---@field checksum string

---@class JavaFileProperties
---@field type "class"|"interface"|"@interface"|"enum"|nil
---@field main boolean|nil
---@field test boolean|nil
---@field importsJunit boolean|nil

---@class MavenImporter
MavenImporter = {}

MavenImporter.status = "Ready"
MavenImporter.statusCode = 0

local prefix = "maven-tools-v2."

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenToolsConfig
local mavenConfig = require(prefix .. "config.maven")

local MavenInfo = {}

---@type table<string, boolean>
local ScanDirs = {}

---@type table<string, JavaFileProperties>
MavenImporter.fileProperties = {}

---@param groupId string
---@param artifactId string
---@param version string|nil
---@return MavenInfo
function MavenInfo:new(groupId, artifactId, version)
    ---@type MavenInfo
    local res = { groupId = groupId or "", artifactId = artifactId or "", version = version or "" }
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

---@param info MavenInfo
---@return string
function MavenImporter.info_to_str(info)
    return info.groupId .. ":" .. info.artifactId .. ":" .. info.version
end

local xml2lua = require("maven-tools-v2.deps.xml2lua.xml2lua")
local xmlTreeHandler = require("maven-tools-v2.deps.xml2lua.xmlhandler.tree")

---@type Path
local cwd

---@type function
local update_callback = function() end

---@type Task_Mgr
local taskMgr = utils.Task_Mgr()

local processingFiles = {}

---@type Task_Mgr
local filesTaskMgr = utils.Task_Mgr()

---@type Array
MavenImporter.pomFiles = utils.Array()

---@type table<string, ProjectInfo>
MavenImporter.mavenInfoToProjectInfoMap = {}

---@type table<string, FileInfoChecksum>
MavenImporter.pomFileToMavenInfoMap = {}

---@type table<string, string>
MavenImporter.pomFileToErrorMap = {}

---@type table<string, MavenPlugin>
MavenImporter.pluginInfoToPluginMap = {}

---@type table<string, table<string, boolean>>
MavenImporter.pomFileIsModuleSet = {}

local penfingFilesQueue = utils.Queue()

---@type table<string, PluginInfo>
local pendingPlugins = {}

---@type table<string, boolean>
local pendingFiles = {}

---@return boolean
function MavenImporter.idle()
    return taskMgr:idle()
end

---@return number
function MavenImporter.progress()
    return taskMgr:progress()
end

---@param pom_file string
---@param refreshProjectInfo any
---@param error string
local function set_project_entry_to_error_state(pom_file, refreshProjectInfo, error)
    if MavenImporter.pomFileToErrorMap[pom_file] == nil then
        MavenImporter.pomFileToErrorMap[pom_file] = error
    end
end

---@param pomFile Path
---@param moduleRelativePathStr string
local function get_module_abs_path(pomFile, moduleRelativePathStr)
    return pomFile:dirname():join(moduleRelativePathStr):join("pom.xml").str
end

---@param xmlPluginSubTree table
---@return MavenInfo
local function xml_plugin_sub_tree_to_maven_info(xmlPluginSubTree)
    return MavenInfo:new(
        xmlPluginSubTree.groupId or "org.apache.maven.plugins",
        xmlPluginSubTree.artifactId,
        xmlPluginSubTree.version
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
                local pluginInfo = xml_plugin_sub_tree_to_maven_info(plugin)
                table.insert(plugins, pluginInfo)
            end
        else
            local pluginInfo = xml_plugin_sub_tree_to_maven_info(xmlProjectSubTree.build.plugins.plugin)
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

---@param projectInfo ProjectInfo
local function start_update_project_files_task(projectInfo, test)
    local projectFiles = {}
    local filesPrefix = test and projectInfo.testSourceDirectory or projectInfo.sourceDirectory

    if filesPrefix == nil then
        return
    end

    local handle
    handle = vim.uv.new_async(function()
        local javaFiles = utils.list_java_files(filesPrefix)

        for _, javaFile in ipairs(javaFiles) do
            local relativePath, count = javaFile:gsub(utils.escape_match_specials(filesPrefix .. "/"), "")

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

                    ---@type ProjectFile
                    local projectFile = { path = javaFile, filename = filename }

                    table.insert(projectFiles[package], projectFile)
                end
            end
        end

        if test then
            projectInfo.testFiles = projectFiles
        else
            projectInfo.files = projectFiles
        end

        if handle ~= nil then
            handle:close()
        end
    end)

    if handle ~= nil then
        handle:send()
    end
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
    local mavenInfoStr = MavenImporter.info_to_str(mavenInfo)

    if MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr] ~= nil then
        return --already processed
    end

    local name
    if xmlProjectSubTree.name == nil or xmlProjectSubTree.name == "" then
        name = xmlProjectSubTree.groupId .. "." .. xmlProjectSubTree.artifactId
    else
        name = xmlProjectSubTree.name
    end

    MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr] = {
        name = name,
        info = mavenInfo,
        dependencies = process_xml_project_sub_tree_dependencies(xmlProjectSubTree),
        plugins = process_xml_project_sub_tree_plugins(xmlProjectSubTree),
        modules = {},
        pomFile = pomFile and pomFile.str or nil,
        files = {},
        testFiles = {},
    }

    if pomFile ~= nil and MavenImporter.pomFileToErrorMap[pomFile.str] ~= nil then
        MavenImporter.pomFileToErrorMap[pomFile.str] = nil
    end

    if pomFile ~= nil then
        MavenImporter.pomFileToMavenInfoMap[pomFile.str] =
            { info = mavenInfo, checksum = tostring(utils.file_checksum(pomFile.str)) }
    end

    if xmlProjectSubTree.modules ~= nil and xmlProjectSubTree.modules.module ~= nil then
        if xmlProjectSubTree.modules.module[1] ~= nil then
            for _, module in pairs(xmlProjectSubTree.modules.module) do
                table.insert(MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].modules, module)
            end
        else
            table.insert(
                MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].modules,
                xmlProjectSubTree.modules.module
            )
        end
    end

    if xmlProjectSubTree.build.sourceDirectory ~= nil then
        MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].sourceDirectory =
            utils.Path(xmlProjectSubTree.build.sourceDirectory).str
    end

    if xmlProjectSubTree.build.scriptSourceDirectory ~= nil then
        MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].scriptSourceDirectory =
            utils.Path(xmlProjectSubTree.build.scriptSourceDirectory).str
    end

    if xmlProjectSubTree.build.testSourceDirectory ~= nil then
        MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].testSourceDirectory =
            utils.Path(xmlProjectSubTree.build.testSourceDirectory).str
    end

    if xmlProjectSubTree.build.outputDirectory ~= nil then
        MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].outputDirectory =
            utils.Path(xmlProjectSubTree.build.outputDirectory).str
    end

    if xmlProjectSubTree.build.testOutputDirectory ~= nil then
        MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].testOutputDirectory =
            utils.Path(xmlProjectSubTree.build.testOutputDirectory).str
    end

    start_update_project_files_task(MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr], false)
    start_update_project_files_task(MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr], true)
end

---@param xmlStr string
---@return string?
function MavenImporter.extract_effective_pom(xmlStr)
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
        return projectXml
    end
end

---@param pomFile Path
---@param refreshProjectInfo ProjectInfo?
local function start_pom_file_processor_task(pomFile, refreshProjectInfo)
    MavenImporter.status = "Processing POM files"
    MavenImporter.statusCode = 2

    assert(pomFile ~= nil, "")

    local pomXmlTree = xmlTreeHandler:new()
    local parser = xml2lua.parser(pomXmlTree)

    taskMgr:run(mavenConfig.importer_pipe_cmd(pomFile.str, { "help:effective-pom" }), function(xmlStr)
        local effectivePomStr = MavenImporter.extract_effective_pom(xmlStr)

        if effectivePomStr ~= nil then
            parser:parse(effectivePomStr)

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
            end
        else
            set_project_entry_to_error_state(pomFile.str, refreshProjectInfo, xmlStr)
        end

        update_callback()
    end)
end

local function substitute_pom_variables(xml, str, depth)
    if xml == nil or str == nil then
        return nil
    end
    depth = depth or 0
    if depth > 10 then
        return str -- Prevent stack overflow on circular references
    end

    local res = str
    local replaced = false

    for var in str:gmatch("%${(.-)}") do
        local clean_var = var:gsub("^project%.", "")
        local value = xml[clean_var]

        if value == nil then
            value = xml["properties." .. clean_var]
        end

        if value ~= nil then
            local escaped_var = utils.escape_match_specials(var)
            res = res:gsub("%${" .. escaped_var .. "}", value)
            replaced = true
        end
    end

    if replaced and res:match("%${.-}") then
        return substitute_pom_variables(xml, res, depth + 1)
    end

    return res
end

---@param pomFile Path
local function start_resolve_maven_info_pom_file_task(pomFile, refreshProjectInfo)
    assert(pomFile ~= nil, "Invalid pom file")

    if MavenImporter.pomFileToMavenInfoMap[pomFile.str] ~= nil then
        return -- already processed
    end

    taskMgr:readFile(pomFile.str, function(pomFileContent)
        local pomXml = xmlTreeHandler:new()
        local pomParser = xml2lua.parser(pomXml)
        local success = pcall(pomParser.parse, pomParser, pomFileContent)

        if not success or pomXml.root == nil or type(pomXml.root.project) ~= "table" then
            set_project_entry_to_error_state(pomFile.str, refreshProjectInfo, "Failed to parse xml file")
            return
        end

        local flatXmlTree = utils.flatten_map(pomXml.root.project)

        local project_node = pomXml.root.project
        local parent_node = project_node.parent or {}

        local raw_groupId = project_node.groupId or parent_node.groupId
        local raw_artifactId = project_node.artifactId
        local raw_version = project_node.version or parent_node.version

        local groupId = substitute_pom_variables(flatXmlTree, raw_groupId)
        local artifactId = substitute_pom_variables(flatXmlTree, raw_artifactId)
        local version = substitute_pom_variables(flatXmlTree, raw_version)

        if groupId ~= nil and artifactId ~= nil then
            local mavenInfo = MavenInfo:new(groupId, artifactId, version)
            local mavenInfoStr = MavenImporter.info_to_str(mavenInfo)

            if MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr] == nil then
                if MavenImporter.status == "Resolving modules" or MavenImporter.status == "Resolving projects" then
                    pendingFiles[pomFile.str] = true
                else
                    set_project_entry_to_error_state(pomFile.str, refreshProjectInfo, "Invalid maven info")
                end
                return
            end

            MavenImporter.mavenInfoToProjectInfoMap[mavenInfoStr].pomFile = pomFile.str
            MavenImporter.pomFileToMavenInfoMap[pomFile.str] =
                { info = mavenInfo, checksum = tostring(utils.file_checksum(pomFile.str)) }
            if MavenImporter.pomFileToErrorMap[pomFile.str] ~= nil then
                MavenImporter.pomFileToErrorMap[pomFile.str] = nil
            end
        end
    end)
end

---@param pomFile string
---@param mavenInfo MavenInfo
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
                MavenImporter.pluginInfoToPluginMap[MavenImporter.info_to_str(mavenInfo)] = plugin
            end
        end
    )
end

local function update_modules_and_pending_plugins()
    for mavenInfoStr, projectInfo in pairs(MavenImporter.mavenInfoToProjectInfoMap) do
        for _, pluginInfo in ipairs(projectInfo.plugins) do
            local pluginInfoStr = MavenImporter.info_to_str(pluginInfo)

            if
                MavenImporter.pluginInfoToPluginMap[pluginInfoStr] == nil
                and pendingPlugins[pluginInfoStr] == nil
                and projectInfo.pomFile ~= nil
            then
                pendingPlugins[pluginInfoStr] = { mavenInfo = pluginInfo, pomFile = projectInfo.pomFile }
            end
        end

        if projectInfo.pomFile ~= nil then
            for i, module in ipairs(projectInfo.modules) do
                if
                    MavenImporter.pomFileToMavenInfoMap[module] ~= nil
                    or MavenImporter.pomFileToErrorMap[module] ~= nil
                then
                    MavenImporter.pomFileIsModuleSet[module][mavenInfoStr] = true
                    if
                        not (
                            MavenImporter.pomFileToMavenInfoMap[module] ~= nil
                            or MavenImporter.pomFileToErrorMap[module] ~= nil
                        ) and utils.is_ignored(module) == false
                    then
                        start_resolve_maven_info_pom_file_task(utils.Path(module))
                    end
                else
                    local modulePath = get_module_abs_path(utils.Path(projectInfo.pomFile), module)
                    projectInfo.modules[i] = modulePath

                    if MavenImporter.pomFileIsModuleSet[modulePath] == nil then
                        MavenImporter.pomFileIsModuleSet[modulePath] = { [mavenInfoStr] = true }
                    else
                        MavenImporter.pomFileIsModuleSet[modulePath][mavenInfoStr] = true
                    end

                    if
                        not (
                            MavenImporter.pomFileToMavenInfoMap[modulePath] ~= nil
                            or MavenImporter.pomFileToErrorMap[modulePath] ~= nil
                        ) and utils.is_ignored(modulePath) == false
                    then
                        start_resolve_maven_info_pom_file_task(utils.Path(modulePath))
                    end
                end
            end
        end
    end
end

local function write_project_cache_file()
    local path = cwd:join(config.localConfigDir)
    local success, _ = utils.create_directories(path.str)

    if success then
        local resFile = io.open(path:join("cache.json").str, "w")

        if resFile then
            local json

            success, json = pcall(vim.json.encode, {
                version = config.version,
                importerChecksum = mavenConfig.importer_checksum(),
                mavenInfoToProjectInfoMap = MavenImporter.mavenInfoToProjectInfoMap,
                pomFileToMavenInfoMap = MavenImporter.pomFileToMavenInfoMap,
                pluginInfoToPluginMap = MavenImporter.pluginInfoToPluginMap,
                pomFileIsModuleSet = MavenImporter.pomFileIsModuleSet,
                pomFileToErrorMap = MavenImporter.pomFileToErrorMap,
            })

            if success then
                resFile:write(json)
            end

            resFile:close()
        end
    end
end

local function update_java_files_properties(dir)
    if dir == nil then
        return
    end

    local cmd
    local args = {}

    if config.OS == "Windows" then
        cmd = "powershell.exe"

        table.insert(args, "-NoProfile")
        table.insert(args, "-Command")
        table.insert(args, "rg")
        table.insert(args, "--no-ignore")
        table.insert(args, "--multiline")
        table.insert(args, "-e")
        table.insert(args, '"class\\s+[^\\s]+|interface\\s+[^\\s]+|enum\\s+[^\\s]+|@interface\\s+[^\\s]+"')
        table.insert(args, "-e")
        table.insert(args, '"static\\s+[^\\s]*\\s*void\\s+main\\s*\\("')
        table.insert(args, "-e")
        table.insert(args, '"@Test"')
        table.insert(args, "-e")
        table.insert(args, '"import\\s+org\\.junit\\."')
        table.insert(args, "-g")
        table.insert(args, '"*.java"')
        table.insert(args, '"' .. dir .. '"')
    else
        cmd = "sh"
        table.insert(args, "-c")
        table.insert(
            args,
            'rg --no-ignore --multiline -e "class\\s+[^\\s]+|interface\\s+[^\\s]+|enum\\s+[^\\s]+|@interface\\s+[^\\s]+" -e "static\\s+[^\\s]*\\s*void\\s+main\\s*\\(" -e "@Test" -e "import\\s+org\\.junit\\." -g "*.java" '
                .. '"'
                .. dir
                .. '"'
        )
    end

    filesTaskMgr:run({ cmd = cmd, args = args }, function(lines)
        for line in lines:gmatch("[^\n]*") do
            for pathStr, match in line:gmatch("(.+)java:(.+)") do
                local path = utils.Path(pathStr .. "java")

                if MavenImporter.fileProperties[path.str] == nil then
                    MavenImporter.fileProperties[path.str] = {}
                end

                local type = match:match("%s*([^%s]+)%s+" .. path:filename():gsub("%.java$", ""))

                if type == "class" or type == "interface" or type == "@interface" or type == "enum" then
                    MavenImporter.fileProperties[path.str].type = type
                end

                local main = match:match("void%s+main%s*%(")

                if main ~= nil then
                    MavenImporter.fileProperties[path.str].main = true
                end

                local test = match:match("@Test")

                if test ~= nil then
                    MavenImporter.fileProperties[path.str].test = true
                end

                local importsJunit = match:match("import%s+org%.junit%.")

                if importsJunit ~= nil then
                    MavenImporter.fileProperties[path.str].importsJunit = true
                end
            end
        end
    end)
end

local function start_update_java_files_properties_task()
    for dir, v in pairs(ScanDirs) do
        if v then
            update_java_files_properties(dir)
        end
    end
end

local function idle_callback_init()
    taskMgr:reset()
    MavenImporter.status = "Resolving projects"
    MavenImporter.statusCode = 3

    taskMgr:set_on_idle_callback(function()
        taskMgr:reset()

        MavenImporter.status = "Resolving modules"

        update_modules_and_pending_plugins()

        MavenImporter.status = "Resolving plugins"
        MavenImporter.statusCode = 4

        taskMgr:set_on_idle_callback(function()
            taskMgr:reset()
            taskMgr:set_on_idle_callback(idle_callback_init)

            for pomFile, v in pairs(pendingFiles) do
                if v then
                    start_pom_file_processor_task(utils.Path(pomFile))
                end
            end

            if taskMgr:idle() then
                local resolve_pending_files = {}
                for pomFile, _ in pairs(pendingFiles) do
                    table.insert(resolve_pending_files, pomFile)
                end

                taskMgr:set_on_idle_callback(function()
                    taskMgr:set_on_idle_callback(function() end)

                    MavenImporter.status = ""
                    MavenImporter.statusCode = 5
                    update_callback()

                    write_project_cache_file()

                    vim.notify("Maven Tools Ready")
                end)

                for _, pomFile in ipairs(resolve_pending_files) do
                    start_resolve_maven_info_pom_file_task(utils.Path(pomFile))
                    pendingFiles[pomFile] = nil
                end

                if taskMgr:idle() then
                    taskMgr:trigger_idle_callback()
                end
            end
        end)

        local pluginTasks = 0

        for pluginInfoStr, pluginInfo in pairs(pendingPlugins) do
            if pluginInfo ~= nil then
                pluginTasks = pluginTasks + 1
                start_resolve_plugin_goals_task(pluginInfo.pomFile, pluginInfo.mavenInfo)
                pendingPlugins[pluginInfoStr] = nil
            end
        end

        if taskMgr:idle() then
            taskMgr:trigger_idle_callback()
        else
            update_callback()
        end
    end)

    for _, pomFile in ipairs(MavenImporter.pomFiles:values()) do
        start_resolve_maven_info_pom_file_task(utils.Path(pomFile))
    end

    if taskMgr:idle() then
        taskMgr:trigger_idle_callback()
    else
        update_callback()
    end
end

function MavenImporter.refresh_projects_files()
    if MavenImporter.status ~= "" then
        return
    end

    filesTaskMgr:set_on_idle_callback(function()
        for _, projectInfo in pairs(MavenImporter.mavenInfoToProjectInfoMap) do
            start_update_project_files_task(projectInfo, false)
            start_update_project_files_task(projectInfo, true)
        end

        filesTaskMgr:set_on_idle_callback(function() end)
        update_callback()
    end)

    start_update_java_files_properties_task()
    filesTaskMgr:trigger_idle_callback_if_idle()
end

---@param pomFile string
local function remove_project(pomFile)
    local projectInfo = MavenImporter.pomFileToMavenInfoMap[pomFile]

    if projectInfo == nil then
        return
    end

    local projectInfoStr = MavenImporter.info_to_str(projectInfo.info)
    local project = MavenImporter.mavenInfoToProjectInfoMap[projectInfoStr]

    if project == nil then
        return
    end

    MavenImporter.mavenInfoToProjectInfoMap[projectInfoStr] = nil
    MavenImporter.pomFileToMavenInfoMap[pomFile] = nil

    for _, module in ipairs(project.modules) do
        local parents = MavenImporter.pomFileIsModuleSet[module]
        MavenImporter.pomFileIsModuleSet[module] = nil

        for info, _ in pairs(parents) do
            if info ~= projectInfoStr then
                if MavenImporter.pomFileIsModuleSet[module] == nil then
                    MavenImporter.pomFileIsModuleSet[module] = { [info] = true }
                else
                    MavenImporter.pomFileIsModuleSet[module][info] = true
                end
            end
        end
    end
end

---@param pomFile string
function MavenImporter.add_new_project(pomFile)
    if type(pomFile) ~= "string" or pomFile:match("[/\\]pom.xml$") == nil then
        return
    end

    taskMgr:set_on_idle_callback(idle_callback_init)
    local path = utils.Path(pomFile)

    if path.str:match("^" .. utils.escape_match_specials(cwd.str)) == nil then
        ScanDirs[path:dirname().str] = true
    end

    MavenImporter.pomFiles:append(path.str)
    start_pom_file_processor_task(path)
end

---@param project ProjectInfo|string
function MavenImporter.refresh_project(project)
    if type(project) == "string" then --error project
        MavenImporter.pomFileToErrorMap[project] = nil

        taskMgr:set_on_idle_callback(idle_callback_init)
        start_pom_file_processor_task(utils.Path(project))
    else
        remove_project(project.pomFile)

        taskMgr:set_on_idle_callback(idle_callback_init)
        start_pom_file_processor_task(utils.Path(project.pomFile))
    end
end

function MavenImporter.update(dir, callback)
    cwd = utils.Path(dir)

    ScanDirs[cwd.str] = true

    update_callback = function()
        vim.schedule(callback)
    end

    MavenImporter.status = "Loading cache"
    MavenImporter.statusCode = 1

    update_callback()
    assert(cwd ~= nil, "")

    filesTaskMgr:set_on_idle_callback(function()
        update_callback()
    end)

    start_update_java_files_properties_task()

    MavenImporter.pomFiles = utils.find_pom_files(cwd.str)
    for _, pomFile in ipairs(config.externalProjects) do
        if type(pomFile) == "string" then
            MavenImporter.pomFiles:append(utils.Path(pomFile).str)
        end
    end

    local cachePath = cwd:join(config.localConfigDir):join("cache.json")

    taskMgr:readFile(cachePath.str, function(cacheStr)
        taskMgr:set_on_idle_callback(idle_callback_init)

        local success, cache = pcall(vim.json.decode, cacheStr)
        local useCache = false

        if success then
            if
                cache.version ~= nil
                and cache.version == config.version
                and cache.importerChecksum ~= nil
                and cache.importerChecksum == mavenConfig.importer_checksum()
                and cache.mavenInfoToProjectInfoMap ~= nil
                and cache.pomFileToMavenInfoMap ~= nil
                and cache.pluginInfoToPluginMap ~= nil
                and cache.pomFileIsModuleSet ~= nil
                and cache.pomFileToErrorMap ~= nil
            then
                useCache = true

                MavenImporter.mavenInfoToProjectInfoMap = cache.mavenInfoToProjectInfoMap
                MavenImporter.pomFileToMavenInfoMap = cache.pomFileToMavenInfoMap
                MavenImporter.pluginInfoToPluginMap = cache.pluginInfoToPluginMap
                MavenImporter.pomFileIsModuleSet = cache.pomFileIsModuleSet
                MavenImporter.pomFileToErrorMap = cache.pomFileToErrorMap
            end
        end

        update_callback()

        if useCache then
            for pomFile, _ in pairs(MavenImporter.pomFileToMavenInfoMap) do
                if
                    MavenImporter.pomFiles:find(pomFile) == nil
                    and (MavenImporter.pomFileIsModuleSet[pomFile] == nil or utils.is_ignored(pomFile))
                then
                    remove_project(pomFile)
                end
            end
        end

        for _, pomFile in ipairs(MavenImporter.pomFiles:values()) do
            pomFile = utils.Path(pomFile)

            if pomFile.str:match("^" .. utils.escape_match_specials(cwd.str)) == nil then
                ScanDirs[pomFile:dirname().str] = true
            end

            if useCache then
                if
                    MavenImporter.pomFileToMavenInfoMap[pomFile.str] == nil
                    or utils.file_checksum(pomFile.str)
                        ~= MavenImporter.pomFileToMavenInfoMap[pomFile.str].checksum
                then
                    if
                        MavenImporter.pomFileToMavenInfoMap[pomFile.str] ~= nil
                        and MavenImporter.mavenInfoToProjectInfoMap[MavenImporter.info_to_str(
                                MavenImporter.pomFileToMavenInfoMap[pomFile.str].info
                            )]
                            ~= nil
                    then
                        MavenImporter.refresh_project(
                            MavenImporter.mavenInfoToProjectInfoMap[MavenImporter.info_to_str(
                                MavenImporter.pomFileToMavenInfoMap[pomFile.str].info
                            )]
                        )
                    else
                        start_pom_file_processor_task(pomFile)
                    end
                elseif MavenImporter.pomFileToMavenInfoMap[pomFile.str] ~= nil then
                    start_update_project_files_task(
                        MavenImporter.mavenInfoToProjectInfoMap[MavenImporter.info_to_str(
                            MavenImporter.pomFileToMavenInfoMap[pomFile.str].info
                        )],
                        false
                    )
                    start_update_project_files_task(
                        MavenImporter.mavenInfoToProjectInfoMap[MavenImporter.info_to_str(
                            MavenImporter.pomFileToMavenInfoMap[pomFile.str].info
                        )],
                        true
                    )
                end
            else
                start_pom_file_processor_task(pomFile)
            end
        end

        taskMgr:trigger_idle_callback_if_idle()
    end)
end

return MavenImporter
