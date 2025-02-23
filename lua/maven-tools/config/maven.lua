---@class Pipe_Cmd
---@field cmd string
---@field args string[]

---@class MavenConfig
MavenToolsMavenConfig = {}

local prefix = "maven-tools."

---@type Utils
local utils = require(prefix .. "utils")

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

MavenToolsMavenConfig.prefer_maven_wrapper = false

---@type "strict"|"lax"|nil
MavenToolsMavenConfig.checksum_policy = nil

MavenToolsMavenConfig.check_plugin_updates = false

---@type string?
MavenToolsMavenConfig.encrypt_master_password = nil

---@type string?
MavenToolsMavenConfig.encrypt_password = nil

---@type string?
MavenToolsMavenConfig.global_settings = nil

---@type string?
MavenToolsMavenConfig.global_toolchains = nil

MavenToolsMavenConfig.ignore_transitive_repositories = false

---@type string?
MavenToolsMavenConfig.settings = nil

---@type string?
MavenToolsMavenConfig.toolchains = nil

---@type boolean
MavenToolsMavenConfig.non_recursive = false

---@type boolean
MavenToolsMavenConfig.no_plugin_registry = false

---@type boolean?
MavenToolsMavenConfig.plugin_updates = nil

---@type boolean?
MavenToolsMavenConfig.snapshot_updates = nil

---@type boolean
MavenToolsMavenConfig.offline = false

---@type string?
MavenToolsMavenConfig.activate_profiles = nil

MavenToolsMavenConfig.also_make = false

MavenToolsMavenConfig.also_make_dependents = false

---@type integer?
MavenToolsMavenConfig.threads = nil

---@type string?
MavenToolsMavenConfig.builder = nil

---@type "never"|"fast"|"end"|nil
MavenToolsMavenConfig.fail_policy = nil

MavenToolsMavenConfig.no_transfer_progress = false

MavenToolsMavenConfig.errors = false

MavenToolsMavenConfig.quiet = false

MavenToolsMavenConfig.debug = false

---@type string?
MavenToolsMavenConfig.importer_jdk = nil

---@type string?
MavenToolsMavenConfig.runner_jdk = nil

---@type string[]
MavenToolsMavenConfig.importer_options = {}

---@type string[]
MavenToolsMavenConfig.runner_options = {}

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

    if options == MavenToolsMavenConfig.importer_options then
        res = res .. "--batch-mode --no-transfer-progress --no-snapshot-updates -DskipTests "
    else
        res = res .. "--color always "
    end

    if MavenToolsMavenConfig.checksum_policy == "lax" then
        res = res .. " --lax-checksums "
    elseif MavenToolsMavenConfig.checksum_policy == "strict" then
        res = res .. " --strict-checksums "
    end

    if MavenToolsMavenConfig.check_plugin_updates then
        res = res .. " --check-plugin-updates "
    end

    if type(MavenToolsMavenConfig.encrypt_master_password) == "string" then
        res = res .. ' "--encrypt-master-password ' .. MavenToolsMavenConfig.encrypt_master_password .. '" '
    end

    if type(MavenToolsMavenConfig.encrypt_password) == "string" then
        res = res .. ' "--encrypt-password ' .. MavenToolsMavenConfig.encrypt_password .. '" '
    end

    if type(MavenToolsMavenConfig.global_settings) == "string" then
        res = res .. ' "--global-settings ' .. MavenToolsMavenConfig.global_settings .. '" '
    end

    if type(MavenToolsMavenConfig.global_toolchains) == "string" then
        res = res .. ' "--global-toolchains ' .. MavenToolsMavenConfig.global_toolchains .. '" '
    end

    if type(MavenToolsMavenConfig.settings) == "string" then
        res = res .. ' "--settings ' .. MavenToolsMavenConfig.settings .. '" '
    end

    if type(MavenToolsMavenConfig.toolchains) == "string" then
        res = res .. ' "--toolchains ' .. MavenToolsMavenConfig.toolchains .. '" '
    end

    if type(MavenToolsMavenConfig.activate_profiles) == "string" then
        res = res .. ' "--activate-profiles ' .. MavenToolsMavenConfig.activate_profiles .. '" '
    end

    if MavenToolsMavenConfig.ignore_transitive_repositories then
        res = res .. " --ignore-transitive-repositories "
    end

    if MavenToolsMavenConfig.non_recursive then
        res = res .. " --non-recursive "
    end

    if type(MavenToolsMavenConfig.plugin_updates) == "boolean" then
        if MavenToolsMavenConfig.plugin_updates then
            res = res .. " --no-plugin-updates "
        else
            res = res .. " --update-plugins "
        end
    end

    if type(MavenToolsMavenConfig.snapshot_updates) == "boolean" then
        if MavenToolsMavenConfig.snapshot_updates then
            res = res .. " --no-snapshot-updates "
        else
            res = res .. " --update-snapshots "
        end
    end

    if MavenToolsMavenConfig.no_plugin_registry then
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

local importer = make_shell_command(MavenToolsMavenConfig.importer_jdk, MavenToolsMavenConfig.importer_options)
local runner = make_shell_command(MavenToolsMavenConfig.runner_jdk, MavenToolsMavenConfig.runner_options)

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
---@return Pipe_Cmd
function MavenToolsMavenConfig.importer_pipe_cmd(file, args)
    return {
        cmd = shell_cmd,
        args = get_importer_args(file, args),
    }
end

---@param file string?
---@param args string[]
---@return Pipe_Cmd
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
    importer = make_shell_command(MavenToolsMavenConfig.importer_jdk, MavenToolsMavenConfig.importer_options)
    runner = make_shell_command(MavenToolsMavenConfig.runner_jdk, MavenToolsMavenConfig.runner_options)
end

return MavenToolsMavenConfig
