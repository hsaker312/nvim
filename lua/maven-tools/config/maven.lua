---@class Pipe_Cmd
---@field cmd string
---@field args string[]

---@class Maven_Config
M = {}

local prefix = "maven-tools."

---@type Utils
local utils = require(prefix .. "utils")

local prefer_maven_wrapper = false

---@type "strict"|"lax"|nil
local checksum_policy = nil

local check_plugin_updates = false

---@type string?
local encrypt_master_password = nil

---@type string?
local encrypt_password = nil

---@type string?
local global_settings = nil

---@type string?
local global_toolchains = nil

local ignore_transitive_repositories = false

---@type string?
local settings = nil

---@type string?
local toolchains = nil

local non_recursive = false

local no_plugin_registry = false

---@type boolean?
local plugin_updates = nil

---@type boolean?
local snapshot_updates = nil

local offline = false

---@type string?
local activate_profiles = nil

local also_make = false

local also_make_dependents = false

---@type integer?
local threads = nil

---@type string?
local builder = nil

---@type "never"|"fast"|"end"|nil
local fail_policy = nil

local no_transfer_progress = false

local errors = false

local quiet = false

local debug = false

---@type string?
local importer_jdk = "/home/helmy/.jdks/azul-1.8.0_412"

---@type string?
local runner_jdk = "/home/helmy/.jdks/azul-1.8.0_412"

local importer_options = { "maven.repo.local=/home/helmy/maven/repos/headless", "branch=headless" }

local runner_options = {
    "maven.repo.local=/home/helmy/maven/repos/headless",
    "branch=headless",
    "org.ops4j.pax.url.mvn.localRepository=/home/helmy/maven/repos/headless",
    "org.ops4j.pax.url.mvn.repositories=http://swproductsrepo.meso-scale.com/nexus/content/groups/headless@id=nexus",
    "org.ops4j.pax.url.mvn.defaultRepositories=/home/helmy/maven/repos/headless",
    "maven.test.skip=true",
    "license.skip.collect=true",
    "msd.clean-database.skip",
}

local function make_shell_command(jdk, options)
    local res = ""

    if type(jdk) == "string" then
        if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
            res = '$env:JAVA_HOME="' .. jdk .. '";'
        else
            res = 'env JAVA_HOME="' .. jdk .. '"'
        end
    end

    res = res .. " mvn "

    if options == importer_options then
        res = res .. "--batch-mode --no-transfer-progress --no-snapshot-updates -DskipTests "
    else
        res = res .. "--color always "
    end

    if checksum_policy == "lax" then
        res = res .. " --lax-checksums "
    elseif checksum_policy == "strict" then
        res = res .. " --strict-checksums "
    end

    if check_plugin_updates then
        res = res .. " --check-plugin-updates "
    end

    if type(encrypt_master_password) == "string" then
        res = res .. ' "--encrypt-master-password ' .. encrypt_master_password .. '" '
    end

    if type(encrypt_password) == "string" then
        res = res .. ' "--encrypt-password ' .. encrypt_password .. '" '
    end

    if type(global_settings) == "string" then
        res = res .. ' "--global-settings ' .. global_settings .. '" '
    end

    if type(global_toolchains) == "string" then
        res = res .. ' "--global-toolchains ' .. global_toolchains .. '" '
    end

    if type(settings) == "string" then
        res = res .. ' "--settings ' .. settings .. '" '
    end

    if type(toolchains) == "string" then
        res = res .. ' "--toolchains ' .. toolchains .. '" '
    end

    if type(activate_profiles) == "string" then
        res = res .. ' "--activate-profiles ' .. activate_profiles .. '" '
    end

    if ignore_transitive_repositories then
        res = res .. " --ignore-transitive-repositories "
    end

    if non_recursive then
        res = res .. " --non-recursive "
    end

    if type(plugin_updates) == "boolean" then
        if plugin_updates then
            res = res .. " --no-plugin-updates "
        else
            res = res .. " --update-plugins "
        end
    end

    if type(snapshot_updates) == "boolean" then
        if snapshot_updates then
            res = res .. " --no-snapshot-updates "
        else
            res = res .. " --update-snapshots "
        end
    end

    if no_plugin_registry then
        res = res .. " --no-plugin-registry "
    end

    if offline then
        res = res .. " --offline "
    end

    for _, value in ipairs(options) do
        res = res .. '"-D' .. value .. '" '
    end

    return res
end

local importer = make_shell_command(importer_jdk, importer_options)
local runner = make_shell_command(runner_jdk, runner_options)

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
    if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
        table.insert(res, "-Command")
    else
        table.insert(res, "-c")
    end

    local arg = ""

    for _, cmd in ipairs(cmds) do
        arg = arg .. get_importer_shell_command(file, cmd)

        if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
            arg = arg .. "; "
        else
            arg = arg .. "&& "
        end
    end

    if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
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
    if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
        table.insert(res, "-Command")
    else
        table.insert(res, "-c")
    end

    local arg = ""

    for _, cmd in ipairs(cmds) do
        arg = arg .. get_runner_shell_command(file, cmd)

        if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
            arg = arg .. "; "
        else
            arg = arg .. "&& "
        end
    end

    if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
        arg = arg:sub(1, #arg - 2)
    else
        arg = arg:sub(1, #arg - 3)
    end

    table.insert(res, arg)

    return res
end

local shell_cmd = package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" and "powershell.exe" or "sh"

---@param file string?
---@param args string[]
---@return Pipe_Cmd
function M.importer_pipe_cmd(file, args)
    return {
        cmd = shell_cmd,
        args = get_importer_args(file, args),
    }
end

---@param file string?
---@param args string[]
---@return Pipe_Cmd
function M.runner_pipe_cmd(file, args)
    return {
        cmd = shell_cmd,
        args = get_runner_args(file, args),
    }
end

---@return string
function M.importer_checksum()
    local cmd = shell_cmd

    for _, arg in ipairs(get_importer_args("", {})) do
        cmd = cmd .. arg
    end

    return utils.str_checksum(cmd)
end

return M
