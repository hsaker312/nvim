---@class PipeCmd
---@field cmd string
---@field args string[]

---@class MavenToolsConfig
MavenToolsMavenConfig = {}

local prefix = "maven-tools."

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type boolean
MavenToolsMavenConfig.preferMavenWrapper = false

---@type "strict"|"lax"|nil
MavenToolsMavenConfig.checksumPolicy = nil

---@type boolean
MavenToolsMavenConfig.checkPluginUpdates = false

---@type string?
MavenToolsMavenConfig.encryptMasterPassword = nil

---@type string?
MavenToolsMavenConfig.encryptPassword = nil

---@type string?
MavenToolsMavenConfig.globalSettings = nil

---@type string?
MavenToolsMavenConfig.globalToolchains = nil

MavenToolsMavenConfig.ignoreTransitiveRepositories = false

---@type string?
MavenToolsMavenConfig.settings = nil

---@type string?
MavenToolsMavenConfig.toolchains = nil

---@type boolean
MavenToolsMavenConfig.nonRecursive = false

---@type boolean
MavenToolsMavenConfig.noPluginRegistry = false

---@type boolean?
MavenToolsMavenConfig.pluginUpdates = nil

---@type boolean?
MavenToolsMavenConfig.snapshotUpdates = nil

---@type boolean
MavenToolsMavenConfig.offline = false

---@type string?
MavenToolsMavenConfig.activateProfiles = nil

MavenToolsMavenConfig.alsoMake = false

MavenToolsMavenConfig.alsoMakeDependents = false

---@type integer?
MavenToolsMavenConfig.threads = nil

---@type string?
MavenToolsMavenConfig.builder = nil

---@type "never"|"fast"|"end"|nil
MavenToolsMavenConfig.failPolicy = nil

MavenToolsMavenConfig.noTransferProgress = false

MavenToolsMavenConfig.errors = false

MavenToolsMavenConfig.quiet = false

MavenToolsMavenConfig.debug = false

---@type string?
MavenToolsMavenConfig.importerJdk = nil

---@type string?
MavenToolsMavenConfig.runnerJdk = nil

---@type string[]
MavenToolsMavenConfig.importerOptions = {}

---@type string[]
MavenToolsMavenConfig.runnerOptions = {}

local function make_shell_command(jdk, options)
    local res = ""

    if type(jdk) == "string" then
        if config.OS == "Windows" then
            res = '$env:JAVA_HOME="' .. jdk .. '";'
        else
            res = 'env JAVA_HOME="' .. jdk .. '"'
        end
    end

    res = res .. " mvn "

    if options == MavenToolsMavenConfig.importerOptions then
        res = res .. "--batch-mode --no-transfer-progress --no-snapshot-updates -DskipTests "
    else
        res = res .. "--color always "
    end

    if MavenToolsMavenConfig.checksumPolicy == "lax" then
        res = res .. " --lax-checksums "
    elseif MavenToolsMavenConfig.checksumPolicy == "strict" then
        res = res .. " --strict-checksums "
    end

    if MavenToolsMavenConfig.checkPluginUpdates then
        res = res .. " --check-plugin-updates "
    end

    if type(MavenToolsMavenConfig.encryptMasterPassword) == "string" then
        res = res .. ' "--encrypt-master-password ' .. MavenToolsMavenConfig.encryptMasterPassword .. '" '
    end

    if type(MavenToolsMavenConfig.encryptPassword) == "string" then
        res = res .. ' "--encrypt-password ' .. MavenToolsMavenConfig.encryptPassword .. '" '
    end

    if type(MavenToolsMavenConfig.globalSettings) == "string" then
        res = res .. ' "--global-settings ' .. MavenToolsMavenConfig.globalSettings .. '" '
    end

    if type(MavenToolsMavenConfig.globalToolchains) == "string" then
        res = res .. ' "--global-toolchains ' .. MavenToolsMavenConfig.globalToolchains .. '" '
    end

    if type(MavenToolsMavenConfig.settings) == "string" then
        res = res .. ' --settings "' .. MavenToolsMavenConfig.settings .. '" '
    end

    if type(MavenToolsMavenConfig.toolchains) == "string" then
        res = res .. ' --toolchains "' .. MavenToolsMavenConfig.toolchains .. '" '
    end

    if type(MavenToolsMavenConfig.activateProfiles) == "string" then
        res = res .. ' "--activate-profiles ' .. MavenToolsMavenConfig.activateProfiles .. '" '
    end

    if MavenToolsMavenConfig.ignoreTransitiveRepositories then
        res = res .. " --ignore-transitive-repositories "
    end

    if MavenToolsMavenConfig.nonRecursive then
        res = res .. " --non-recursive "
    end

    if type(MavenToolsMavenConfig.pluginUpdates) == "boolean" then
        if MavenToolsMavenConfig.pluginUpdates then
            res = res .. " --no-plugin-updates "
        else
            res = res .. " --update-plugins "
        end
    end

    if type(MavenToolsMavenConfig.snapshotUpdates) == "boolean" then
        if MavenToolsMavenConfig.snapshotUpdates then
            res = res .. " --no-snapshot-updates "
        else
            res = res .. " --update-snapshots "
        end
    end

    if MavenToolsMavenConfig.noPluginRegistry then
        res = res .. " --no-plugin-registry "
    end

    if MavenToolsMavenConfig.offline then
        res = res .. " --offline "
    end

    for _, value in ipairs(options) do
        res = res .. '"-D' .. value .. '" '
    end

    return res
end

local importer = make_shell_command(MavenToolsMavenConfig.importerJdk, MavenToolsMavenConfig.importerOptions)
local runner = make_shell_command(MavenToolsMavenConfig.runnerJdk, MavenToolsMavenConfig.runnerOptions)

local function get_importer_shell_command(file, cmd)
    local res = importer

    if type(file) == "string" then
        res = res .. '-f "' .. file .. '" '
    end

    return res .. cmd .. " "
end

local function get_runner_shell_command(file, cmd)
    local res = runner

    if type(file) == "string" then
        res = res .. '-f "' .. file .. '" '
    end

    return res .. cmd .. " "
end

---@param file string?
---@param cmds string[]
---@return string[]
local function get_importer_args(file, cmds)
    local res = {}

    if config.OS == "Windows" then
        table.insert(res, "-NoProfile")
        table.insert(res, "-Command")
    else
        table.insert(res, "-c")
    end

    local arg = ""

    for _, cmd in ipairs(cmds) do
        arg = arg .. get_importer_shell_command(file, cmd)

        if config.OS == "Windows" then
            arg = arg .. "; "
        else
            arg = arg .. "&& "
        end
    end

    if config.OS == "Windows" then
        arg = arg:sub(1, #arg - 2)
    else
        arg = arg:sub(1, #arg - 3)
    end

    table.insert(res, arg)

    return res
end

---@param file string?
---@param cmds string[]
---@return string[]
local function get_runner_args(file, cmds)
    local res = {}
    if config.OS == "Windows" then
        table.insert(res, "-NoProfile")
        table.insert(res, "-Command")
    else
        table.insert(res, "-c")
    end

    local arg = ""

    for _, cmd in ipairs(cmds) do
        arg = arg .. get_runner_shell_command(file, cmd)

        if config.OS == "Windows" then
            arg = arg .. "; "
        else
            arg = arg .. "&& "
        end
    end

    if config.OS == "Windows" then
        arg = arg:sub(1, #arg - 2)
    else
        arg = arg:sub(1, #arg - 3)
    end

    table.insert(res, arg)

    return res
end

local shell_cmd = config.OS == "Windows" and "powershell.exe" or "sh"

---@param file string?
---@param args string[]
---@return PipeCmd
function MavenToolsMavenConfig.importer_pipe_cmd(file, args)
    return {
        cmd = shell_cmd,
        args = get_importer_args(file, args),
    }
end

---@param file string?
---@param args string[]
---@return PipeCmd
function MavenToolsMavenConfig.runner_pipe_cmd(file, args)
    return {
        cmd = shell_cmd,
        args = get_runner_args(file, args),
    }
end

---@return string
function MavenToolsMavenConfig.importer_checksum()
    local cmd = shell_cmd

    for _, arg in ipairs(get_importer_args("", {})) do
        cmd = cmd .. arg
    end

    return utils.str_checksum(cmd)
end

function MavenToolsMavenConfig.update()
    importer = make_shell_command(MavenToolsMavenConfig.importerJdk, MavenToolsMavenConfig.importerOptions)
    runner = make_shell_command(MavenToolsMavenConfig.runnerJdk, MavenToolsMavenConfig.runnerOptions)
end

return MavenToolsMavenConfig
