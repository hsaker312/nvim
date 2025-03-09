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
---@field prefer_maven_wrapper boolean|nil
---@field checksum_policy "strict"|"lax"|nil
---@field check_plugin_updates boolean|nil
---@field encrypt_master_password string|nil
---@field encrypt_password string|nil
---@field global_settings string|nil
---@field global_toolchains string|nil
---@field ignore_transitive_repositories string|nil
---@field settings string|nil
---@field toolchains string|nil
---@field non_recursive boolean|nil
---@field no_plugin_registry boolean|nil
---@field plugin_updates boolean|nil
---@field snapshot_updates boolean|nil
---@field offline boolean|nil
---@field activate_profiles string|nil
---@field also_make boolean|nil
---@field also_make_dependents boolean|nil
---@field threads integer|nil
---@field builder string|nil
---@field fail_policy "never"|"fast"|"end"|nil
---@field no_transfer_progress boolean|nil
---@field errors boolean|nil
---@field quiet boolean|nil
---@field debug boolean|nil
---@field importer_jdk string|nil
---@field runner_jdk string|nil
---@field importer_options string[]|nil
---@field runner_options string[]|nil

---@class MavenToolsOpts
---@field config MavenToolsConfigOpts|nil
---@field maven MavenToolsMavenOpts|nil

---@class MavenTools
MavenTools = {}

local prefix = "maven-tools."

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@type MavenToolsConfig
local maven_config = require(prefix .. "config.maven")

---@type MavenImporterNew
local newImporter = require(prefix .. "maven.importer_new")

---@type MavenUtils
local utils = require(prefix .. "utils")

----@type MavenImporter
local maven_importer = require(prefix .. "maven.importer")


local function toggle()
    require("maven-tools.ui.main"):toggle_main_win()
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
    vim.g.MavernTools = MavenTools

    vim.schedule(function()
        configure(opts)

        vim.schedule(function()
            local local_config_path = vim.loop.cwd() .. "/" .. config.localConfigDir .. "/maven.lua"

            if io.open(local_config_path, "r") ~= nil then
                vim.api.nvim_command("source " .. local_config_path)
            end

            vim.schedule(function()
                if config.autoStart then
                    require("maven-tools.ui.main").init()
                end

                vim.api.nvim_create_user_command("MavenToolsToggle", 'lua require("maven-tools.ui.main").toggle_main_win()', {})
                vim.api.nvim_create_user_command("MavenToolsShow", 'lua require("maven-tools.ui.main").show_main_win()', {})
                vim.api.nvim_create_user_command("MavenToolsHide", 'lua require("maven-tools.ui.main").hide_main_win()', {})
                vim.api.nvim_create_user_command("MavenToolsRun", 'lua require("maven-tools.ui.main").run(0)', {})
                vim.api.nvim_create_user_command("MavenToolsAddLocalDependency", 'lua require("maven-tools.ui.main").add_local_dependency(0)', {})
                vim.api.nvim_create_user_command("MavenToolsAddDependency", 'lua require("maven-tools.ui.main").add_dependency(0)', {})
            end)
        end)
    end)

    return MavenTools
end

return MavenTools
