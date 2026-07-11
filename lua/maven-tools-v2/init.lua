---@class MavenToolsConfigOpts
---@field recursivePomSearch boolean|nil
---@field multiproject boolean|nil
---@field refreshOnStartup boolean|nil
---@field localConfigDir boolean|nil
---@field maxParallelJobs boolean|nil
---@field ignoreFiles boolean|nil
---@field defaultFilter string|nil
---@field lifecycleCommands string[]|nil

---@class MavenToolsMavenOpts
---@field preferMavenWrapper boolean|nil
---@field mavenExecutable string|nil
---@field checksumPolicy "strict"|"lax"|nil
---@field checkPluginUpdates boolean|nil
---@field encryptMasterPassword string|nil
---@field encryptPassword string|nil
---@field globalSettings string|nil
---@field globalToolchains string|nil
---@field ignoreTransitiveRepositories string|nil
---@field settings string|nil
---@field toolchains string|nil
---@field nonRecursive boolean|nil
---@field noPluginRegistry boolean|nil
---@field pluginUpdates boolean|nil
---@field snapshotUpdates boolean|nil
---@field offline boolean|nil
---@field activateProfiles string|nil
---@field alsoMake boolean|nil
---@field alsoMakeDependents boolean|nil
---@field threads integer|nil
---@field builder string|nil
---@field failPolicy "never"|"fast"|"end"|nil
---@field noTransferProgress boolean|nil
---@field errors boolean|nil
---@field quiet boolean|nil
---@field debug boolean|nil
---@field importerJdk string|nil
---@field runnerJdk string|nil
---@field importerOptions string[]|nil
---@field runner_options string[]|nil

---@class MavenToolsOpts
---@field config MavenToolsConfigOpts|nil
---@field maven MavenToolsMavenOpts|nil

---@class MavenTools
MavenTools = {}

local prefix = "maven-tools-v2."

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenToolsMavenConfig
local maven_config = require(prefix .. "config.maven")

---@type MavenImporter
local importer = require(prefix .. "maven.importer")

---@type MavenUtils
local utils = require(prefix .. "utils")

local function toggle()
    require("maven-tools-v2.ui.main"):toggle_main_win()
end

---@param opts MavenToolsOpts|nil
local function configure(opts)
    if opts == nil or type(opts) ~= "table" then
        return
    end

    if opts.config ~= nil and type(opts.config) == "table" then
        for k, v in pairs(opts.config) do
            config[k] = v
        end
    end

    if opts.maven ~= nil and type(opts.maven) == "table" then
        for k, v in pairs(opts.maven) do
            maven_config[k] = v
        end
    end

    maven_config.update()
end

---@param opts MavenToolsOpts
function MavenTools.override(opts)
    configure(opts)
end

---@param opts MavenToolsOpts|nil
function MavenTools.setup(opts)
    vim.g.MavenTools = MavenTools
    -- Backward compatibility spelling fallback
    vim.g.MavernTools = MavenTools

    configure(opts)

    local local_config_path = vim.uv.cwd() .. "/" .. config.localConfigDir .. "/maven.lua"

    if io.open(local_config_path, "r") ~= nil then
        vim.api.nvim_command("source " .. local_config_path)
    end

    if config.autoStart then
        vim.schedule(function()
            require("maven-tools-v2.ui.main").init()
        end)
    end

    vim.api.nvim_create_user_command(
        "MavenToolsToggle",
        'lua require("maven-tools-v2.ui.main").toggle_main_win()',
        {}
    )
    vim.api.nvim_create_user_command(
        "MavenToolsShow",
        'lua require("maven-tools-v2.ui.main").show_main_win()',
        {}
    )
    vim.api.nvim_create_user_command(
        "MavenToolsHide",
        'lua require("maven-tools-v2.ui.main").hide_main_win()',
        {}
    )
    vim.api.nvim_create_user_command("MavenToolsRun", 'lua require("maven-tools-v2.ui.main").run(0)', {})
    vim.api.nvim_create_user_command(
        "MavenToolsStop",
        function()
            local stopped = require("maven-tools-v2.maven.runner").terminate()
            if stopped then
                vim.notify("Maven goal execution stopped!", vim.log.levels.WARN)
            else
                vim.notify("No maven goal is currently running.", vim.log.levels.INFO)
            end
        end,
        {}
    )
    vim.api.nvim_create_user_command(
        "MavenToolsAddLocalDependency",
        'lua require("maven-tools-v2.ui.main").add_local_dependency(0)',
        {}
    )
    vim.api.nvim_create_user_command(
        "MavenToolsAddDependency",
        'lua require("maven-tools-v2.ui.main").add_dependency(0)',
        {}
    )

    return MavenTools
end

return MavenTools
