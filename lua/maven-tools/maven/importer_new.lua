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

---@class ProjectFile
---@field path string
---@field filename string

---@class ProjectInfo
---@field name string
---@field info MavenInfoNew
---@field dependencies MavenDependency[]
---@field plugins MavenInfoNew[]
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
---@field mavenInfo MavenInfoNew
---@field pomFile string

---@class MavenPlugin
---@field goal string
---@field commands string[]

---@class FileInfoChecksumNew
---@field info MavenInfoNew
---@field checksum string

---@class MavenImporterNew
MavenImporterNew = {}

MavenImporterNew.status = "Ready"

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
    --
    -- setmetatable(res, {
    --     ---@param obj MavenInfoNew
    --     __tostring = function(obj)
    --         return obj.groupId .. ":" .. obj.artifactId .. ":" .. obj.version
    --     end,
    -- })

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

---@param info MavenInfoNew
---@return string
function MavenImporterNew.info_to_str(info)
    return info.groupId .. ":" .. info.artifactId .. ":" .. info.version
end

local xml2lua = require("maven-tools.deps.xml2lua.xml2lua")
local xmlTreeHandler = require("maven-tools.deps.xml2lua.xmlhandler.tree")

---@type Path
local cwd

---@type function
local update_callback = nil

---@type Task_Mgr
local taskMgr = utils.Task_Mgr()

local processingFiles = {}

---@type Task_Mgr
local filesTaskMgr = utils.Task_Mgr()

MavenImporterNew.pomFiles = nil
---@type table<string, ProjectInfo>
MavenImporterNew.mavenInfoToProjectInfoMap = {}

---@type table<string, FileInfoChecksumNew>
MavenImporterNew.pomFileToMavenInfoMap = {}

---@type table<string, string>
MavenImporterNew.pomFileToErrorMap = {}

---@type table<string, MavenPlugin>
MavenImporterNew.pluginInfoToPluginMap = {}

---@type table<string, table<string, boolean>>
MavenImporterNew.pomFileIsModuleSet = {}

---@type table<string, PluginInfo>
local pendingPlugins = {}

---@type table<string, boolean>
local pendingFiles = {}

---@return boolean
function MavenImporterNew.idle()
    return taskMgr:idle()
end

--- @return number
function MavenImporterNew.progress()
    return taskMgr:progress()
end

---@param pom_file string
---@param refreshProjectInfo any
---@param error string
local function set_project_entry_to_error_state(pom_file, refreshProjectInfo, error)
    if MavenImporterNew.pomFileToErrorMap[pom_file] == nil then
        MavenImporterNew.pomFileToErrorMap[pom_file] = error
    end
end

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
                local pluginInfoStr = MavenImporterNew.info_to_str(pluginInfo)

                table.insert(plugins, pluginInfo)
            end
        else
            local pluginInfo = xml_plugin_sub_tree_to_maven_info(xmlProjectSubTree.build.plugins.plugin)
            local pluginInfoStr = MavenImporterNew.info_to_str(pluginInfo)

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
local function update_project_files(projectInfo, test)
    local projectFiles = {}
    local filesPrefix = test and projectInfo.testSourceDirectory or projectInfo.sourceDirectory

    if filesPrefix == nil then
        return
    end

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

                -- if processingFiles[javaFile] == nil then
                -- processingFiles[javaFile] = true
                --
                -- filesTaskMgr:readFile(javaFile, function(lines)
                --     local className = filename:gsub("%.java$", "")
                --     local match = lines:match("(class)%s+" .. className)
                --
                --     if match == nil then
                --         match = lines:match("(@interface)%s+" .. className)
                --     end
                --
                --     if match == nil then
                --         match = lines:match("(interface)%s+" .. className)
                --     end
                --
                --     if match == nil then
                --         match = lines:match("(enum)%s+" .. className)
                --     end
                --
                --     if match ~= nil then
                --         projectFile.type = match
                --     end
                --
                --     match = lines:match("public%s+static%s+void%s+main%s*%(%s*String%s*%[%s*%]")
                --
                --     if match == nil then
                --         match = lines:match("public%s+static%s+void%s+main%s*%(%s*String%s*%.%.%.")
                --     end
                --
                --     if match == nil then
                --         match = lines:match("import%s+org%.junit%.")
                --
                --         if match ~= nil then
                --             match = lines:match("@Test")
                --         end
                --     end
                --
                --     if match ~= nil then
                --         projectFile.runnable = true
                --     end
                --
                --     processingFiles[javaFile] = nil
                -- end)
                -- end
            end
        end
    end

    if test then
        projectInfo.testFiles = projectFiles
    else
        projectInfo.files = projectFiles
    end

    update_callback()
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
    local mavenInfoStr = MavenImporterNew.info_to_str(mavenInfo)

    if MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr] ~= nil then
        return --already processed
    end

    local name
    if xmlProjectSubTree.name == nil or xmlProjectSubTree.name == "" then
        name = xmlProjectSubTree.groupId .. "." .. xmlProjectSubTree.artifactId
    else
        name = xmlProjectSubTree.name
    end

    MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr] = {
        name = name,
        info = mavenInfo,
        dependencies = process_xml_project_sub_tree_dependencies(xmlProjectSubTree),
        plugins = process_xml_project_sub_tree_plugins(xmlProjectSubTree),
        modules = {},
        pomFile = pomFile and pomFile.str or nil,
        files = {},
        testFiles = {},
    }

    if pomFile ~= nil and MavenImporterNew.pomFileToErrorMap[pomFile.str] ~= nil then
        MavenImporterNew.pomFileToErrorMap[pomFile.str] = nil
    end

    if pomFile ~= nil then
        MavenImporterNew.pomFileToMavenInfoMap[pomFile.str] =
            { info = mavenInfo, checksum = tostring(utils.file_checksum(pomFile.str)) }
    end

    if xmlProjectSubTree.modules ~= nil and xmlProjectSubTree.modules.module ~= nil then
        if xmlProjectSubTree.modules.module[1] ~= nil then
            for _, module in pairs(xmlProjectSubTree.modules.module) do
                table.insert(MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].modules, module)
            end
        else
            table.insert(
                MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].modules,
                xmlProjectSubTree.modules.module
            )
        end
    end

    if xmlProjectSubTree.build.sourceDirectory ~= nil then
        MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].sourceDirectory =
            utils.Path(xmlProjectSubTree.build.sourceDirectory).str
    end

    if xmlProjectSubTree.build.scriptSourceDirectory ~= nil then
        MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].scriptSourceDirectory =
            utils.Path(xmlProjectSubTree.build.scriptSourceDirectory).str
    end

    if xmlProjectSubTree.build.testSourceDirectory ~= nil then
        MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].testSourceDirectory =
            utils.Path(xmlProjectSubTree.build.testSourceDirectory).str
    end

    if xmlProjectSubTree.build.outputDirectory ~= nil then
        MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].outputDirectory =
            utils.Path(xmlProjectSubTree.build.outputDirectory).str
    end

    if xmlProjectSubTree.build.testOutputDirectory ~= nil then
        MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].testOutputDirectory =
            utils.Path(xmlProjectSubTree.build.testOutputDirectory).str
    end

    update_project_files(MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr], false)
    update_project_files(MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr], true)
end

---@param pomFile Path
---@param refreshProjectInfo ProjectInfo?
local function start_pom_file_processor_task(pomFile, refreshProjectInfo)
    MavenImporterNew.status = "Processing POM files"

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
            set_project_entry_to_error_state(pomFile.str, refreshProjectInfo, xmlStr)
            -- callback(nil)
        end

        update_callback()
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

    if MavenImporterNew.pomFileToMavenInfoMap[pomFile.str] ~= nil then
        return -- already processed
    end

    taskMgr:readFile(pomFile.str, function(pomFileContent)
        local pomXml = xmlTreeHandler:new()
        local pomParser = xml2lua.parser(pomXml)
        local success = pcall(pomParser.parse, pomParser, pomFileContent)

        if not success then
            set_project_entry_to_error_state(pomFile.str, refreshProjectInfo, "Failed to parse xml file")
            return
        end

        local flatXmlTree = utils.flatten_map(pomXml.root.project)

        local groupId = substitute_pom_variables(flatXmlTree, pomXml.root.project.groupId)
        local artifactId = substitute_pom_variables(flatXmlTree, pomXml.root.project.artifactId)
        local version = substitute_pom_variables(flatXmlTree, pomXml.root.project.version)

        if groupId ~= nil and artifactId ~= nil then
            local mavenInfo = MavenInfo:new(groupId, artifactId, version)
            local mavenInfoStr = MavenImporterNew.info_to_str(mavenInfo)

            if MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr] == nil then
                set_project_entry_to_error_state(pomFile.str, refreshProjectInfo, "Invalid maven info")
                return
            end

            MavenImporterNew.mavenInfoToProjectInfoMap[mavenInfoStr].pomFile = pomFile.str
            MavenImporterNew.pomFileToMavenInfoMap[pomFile.str] =
                { info = mavenInfo, checksum = tostring(utils.file_checksum(pomFile.str)) }
            if MavenImporterNew.pomFileToErrorMap[pomFile.str] ~= nil then
                MavenImporterNew.pomFileToErrorMap[pomFile.str] = nil
            end
        end

        update_callback()
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
                MavenImporterNew.pluginInfoToPluginMap[MavenImporterNew.info_to_str(mavenInfo)] = plugin
            end

            update_callback()
        end
    )
end

local function update_modules_and_pending_plugins()
    for mavenInfoStr, projectInfo in pairs(MavenImporterNew.mavenInfoToProjectInfoMap) do
        for _, pluginInfo in ipairs(projectInfo.plugins) do
            local pluginInfoStr = MavenImporterNew.info_to_str(pluginInfo)

            if
                MavenImporterNew.pluginInfoToPluginMap[pluginInfoStr] == nil
                and pendingPlugins[pluginInfoStr] == nil
                and projectInfo.pomFile ~= nil
            then
                pendingPlugins[pluginInfoStr] = { mavenInfo = pluginInfo, pomFile = projectInfo.pomFile }
            end
        end

        if projectInfo.pomFile ~= nil then
            for i, module in ipairs(projectInfo.modules) do
                if
                    MavenImporterNew.pomFileToMavenInfoMap[module] ~= nil
                    or MavenImporterNew.pomFileToErrorMap[module] ~= nil
                then
                    MavenImporterNew.pomFileIsModuleSet[module][mavenInfoStr] = true
                    if
                        not (
                            MavenImporterNew.pomFileToMavenInfoMap[module] ~= nil
                            or MavenImporterNew.pomFileToErrorMap[module] ~= nil
                        )
                    then
                        pendingFiles[module] = true
                    end
                else
                    local modulePath = get_module_abs_path(utils.Path(projectInfo.pomFile), module)
                    projectInfo.modules[i] = modulePath

                    if MavenImporterNew.pomFileIsModuleSet[modulePath] == nil then
                        MavenImporterNew.pomFileIsModuleSet[modulePath] = { [mavenInfoStr] = true }
                    else
                        MavenImporterNew.pomFileIsModuleSet[modulePath][mavenInfoStr] = true
                    end

                    if
                        not (
                            MavenImporterNew.pomFileToMavenInfoMap[modulePath] ~= nil
                            or MavenImporterNew.pomFileToErrorMap[modulePath] ~= nil
                        )
                    then
                        pendingFiles[modulePath] = true
                    end
                end
            end
        end

        update_callback()
    end
end

local function update_projects_all_files()
    for _, projectInfo in pairs(MavenImporterNew.mavenInfoToProjectInfoMap) do
        update_project_files(projectInfo, false)
        update_project_files(projectInfo, true)
    end
end

local function write_project_cache_file()
    local path = cwd:join(config.localConfigDir)
    local success, _ = utils.create_directories(path.str)

    if success then
        local resFile = io.open(path:join("cache.json").str, "w")

        if resFile then
            vim.schedule(function()
                local json

                success, json = pcall(vim.fn.json_encode, {
                    version = config.version,
                    importerChecksum = mavenConfig.importer_checksum(),
                    mavenInfoToProjectInfoMap = MavenImporterNew.mavenInfoToProjectInfoMap,
                    pomFileToMavenInfoMap = MavenImporterNew.pomFileToMavenInfoMap,
                    pluginInfoToPluginMap = MavenImporterNew.pluginInfoToPluginMap,
                    pomFileIsModuleSet = MavenImporterNew.pomFileIsModuleSet,
                    pomFileToErrorMap = MavenImporterNew.pomFileToErrorMap,
                })

                if success then
                    resFile:write(json)
                end

                resFile:close()
            end)
        end
    end
end

---@class JavaFileProperties
---@field type "class"|"interface"|"@interface"|"enum"|nil
---@field main boolean|nil
---@field test boolean|nil
---@field importsJunit boolean|nil

---@type table<string, JavaFileProperties>
MavenImporterNew.fileProperties = {}

local function start_update_java_files_properties_task()
    local cmd
    local args = {}

    if config.OS == "Windows" then
        cmd = "powershell.exe"

        table.insert(args, "-NoProfile")
        table.insert(args, "-Command")
        table.insert(args, "rg")
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
        table.insert(args, '"' .. cwd.str .. '"')
    else
        cmd = "sh"
        table.insert(args, "-c")
        table.insert(
            args,
            'rg --multiline -e "class\\s+[^\\s]+|interface\\s+[^\\s]+|enum\\s+[^\\s]+|@interface\\s+[^\\s]+" -e "static\\s+[^\\s]*\\s*void\\s+main\\s*\\(" -e "@Test" -e "import\\s+org\\.junit\\." -g "*.java" '
                .. '"'
                .. cwd.str
                .. '"'
        )
    end

    filesTaskMgr:run({ cmd = cmd, args = args }, function(lines)
        print(lines)

        for line in lines:gmatch("[^\n]*") do
            for pathStr, match in line:gmatch("(.+)java:(.+)") do
                -- if match:match("[%*/]") == nil then
                local path = utils.Path(pathStr .. "java")

                if MavenImporterNew.fileProperties[path.str] == nil then
                    MavenImporterNew.fileProperties[path.str] = {}
                end

                local type = match:match("%s*([^%s]+)%s+" .. path:filename():gsub("%.java$", ""))

                if type == "class" or type == "interface" or type == "@interface" or type == "enum" then
                    MavenImporterNew.fileProperties[path.str].type = type
                end

                local main = match:match("void%s+main%s*%(")

                if main ~= nil then
                    MavenImporterNew.fileProperties[path.str].main = true
                end

                local test = match:match("@Test")

                if test ~= nil then
                    MavenImporterNew.fileProperties[path.str].test = true
                end

                local importsJunit = match:match("import%s+org%.junit%.")

                if importsJunit ~= nil then
                    MavenImporterNew.fileProperties[path.str].importsJunit = true
                end
            end
        end

        update_callback()
    end)
end

local function idle_callback_init()
    taskMgr:reset()
    MavenImporterNew.status = "Resolving projects"

    -- print(MavenToolsImporterNew.status)

    taskMgr:set_on_idle_callback(function()
        taskMgr:reset()

        MavenImporterNew.status = "Resolving modules"
        -- print(MavenToolsImporterNew.status)

        update_modules_and_pending_plugins()

        MavenImporterNew.status = "Resolving plugins"
        -- print(MavenToolsImporterNew.status)

        taskMgr:set_on_idle_callback(function()
            taskMgr:reset()
            taskMgr:set_on_idle_callback(idle_callback_init)

            for pomFile, v in pairs(pendingFiles) do
                if v then
                    start_pom_file_processor_task(utils.Path(pomFile))
                end
            end

            if taskMgr:idle() then
                for pomFile, _ in pairs(pendingFiles) do
                    pendingFiles[pomFile] = nil
                end

                MavenImporterNew.status = ""
                update_callback()

                write_project_cache_file()
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
        -- update_projects_all_files()

        taskMgr:trigger_idle_callback_if_idle()
    end)

    for _, pomFile in ipairs(MavenImporterNew.pomFiles) do
        start_resolve_maven_info_pom_file_task(utils.Path(pomFile))
    end

    for pomFile, v in pairs(pendingFiles) do
        if v then
            start_resolve_maven_info_pom_file_task(utils.Path(pomFile))
            pendingFiles[pomFile] = nil
        end
    end

    taskMgr:trigger_idle_callback_if_idle()
end

---@param pomFile string
local function remove_project(pomFile)
    local projectInfo = MavenImporterNew.pomFileToMavenInfoMap[pomFile]

    if projectInfo == nil then
        return
    end

    local projectInfoStr = MavenImporterNew.info_to_str(projectInfo.info)
    local project = MavenImporterNew.mavenInfoToProjectInfoMap[projectInfoStr]

    if project == nil then
        return
    end

    MavenImporterNew.mavenInfoToProjectInfoMap[projectInfoStr] = nil
    MavenImporterNew.pomFileToMavenInfoMap[pomFile] = nil

    for _, module in ipairs(project.modules) do
        local parents = MavenImporterNew.pomFileIsModuleSet[module]
        MavenImporterNew.pomFileIsModuleSet[module] = nil

        for info, _ in pairs(parents) do
            if info ~= projectInfoStr then
                if MavenImporterNew.pomFileIsModuleSet[module] == nil then
                    MavenImporterNew.pomFileIsModuleSet[module] = { [info] = true }
                else
                    MavenImporterNew.pomFileIsModuleSet[module][info] = true
                end
            end
        end
    end
end

---@param project ProjectInfo|string
function MavenImporterNew.refresh_prject(project)
    if type(project) == "string" then --TODO: error project
    else
        remove_project(project.pomFile)

        taskMgr:set_on_idle_callback(idle_callback_init)
        start_pom_file_processor_task(utils.Path(project.pomFile))
        taskMgr:trigger_idle_callback_if_idle()
    end
end

function MavenImporterNew.update(dir, callback)
    cwd = utils.Path(dir)

    update_callback = function()
        vim.schedule(callback)
    end

    MavenImporterNew.status = "Looking of pom.xml files"

    update_callback()
    assert(cwd ~= nil, "")

    filesTaskMgr:set_on_idle_callback(function()
        print("updated file types")
        update_callback()
    end)

    start_update_java_files_properties_task()

    MavenImporterNew.pomFiles = utils.find_pom_files(cwd.str)

    local cachePath = cwd:join(config.localConfigDir):join("cache.json")

    taskMgr:readFile(cachePath.str, function(cacheStr)
        vim.schedule(function()
            taskMgr:set_on_idle_callback(idle_callback_init)
            local success, cache = pcall(vim.fn.json_decode, cacheStr)
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

                    MavenImporterNew.mavenInfoToProjectInfoMap = cache.mavenInfoToProjectInfoMap
                    MavenImporterNew.pomFileToMavenInfoMap = cache.pomFileToMavenInfoMap
                    MavenImporterNew.pluginInfoToPluginMap = cache.pluginInfoToPluginMap
                    MavenImporterNew.pomFileIsModuleSet = cache.pomFileIsModuleSet
                    MavenImporterNew.pomFileToErrorMap = cache.pomFileToErrorMap
                end
            end

            update_callback()

            if useCache then
                for pomFile, _ in pairs(MavenImporterNew.pomFileToMavenInfoMap) do
                    if
                        MavenImporterNew.pomFiles:find(pomFile) == nil
                        and MavenImporterNew.pomFileIsModuleSet[pomFile] == nil
                    then
                        remove_project(pomFile)
                    end
                end

                ---TODO: remove error projects
            end

            for _, pomFile in ipairs(MavenImporterNew.pomFiles) do
                pomFile = utils.Path(pomFile)
                if useCache then
                    if
                        MavenImporterNew.pomFileToMavenInfoMap[pomFile.str] == nil
                        or utils.file_checksum(pomFile.str)
                            ~= MavenImporterNew.pomFileToMavenInfoMap[pomFile.str].checksum
                    then
                        if
                            MavenImporterNew.mavenInfoToProjectInfoMap[MavenImporterNew.info_to_str(
                                MavenImporterNew.pomFileToMavenInfoMap[pomFile.str].info
                            )] ~= nil
                        then
                            MavenImporterNew.refresh_prject(
                                MavenImporterNew.mavenInfoToProjectInfoMap[MavenImporterNew.info_to_str(
                                    MavenImporterNew.pomFileToMavenInfoMap[pomFile.str].info
                                )]
                            )
                        else
                        end
                        start_pom_file_processor_task(pomFile)
                    elseif MavenImporterNew.pomFileToMavenInfoMap[pomFile.str] ~= nil then
                        update_project_files(
                            MavenImporterNew.mavenInfoToProjectInfoMap[MavenImporterNew.info_to_str(
                                MavenImporterNew.pomFileToMavenInfoMap[pomFile.str].info
                            )],
                            false
                        )
                        update_project_files(
                            MavenImporterNew.mavenInfoToProjectInfoMap[MavenImporterNew.info_to_str(
                                MavenImporterNew.pomFileToMavenInfoMap[pomFile.str].info
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
    end)
end

return MavenImporterNew
