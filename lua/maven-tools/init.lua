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

-- local my_require = require
--
-- require = function(str)
--     if str:match("^Xml") then
--         my_require(prefix .. "dep.xml2lua." .. str)
--     else
--         my_require(str)
--     end
-- end
--

--

---@type MavenImporter
local maven_importer = require(prefix .. "maven.importer")

local main_win = vim.api.nvim_get_current_win()

MavenTools.show_win = function()
    if maven_win == nil and maven_buf ~= nil then
        maven_win = create_tree_window(maven_buf)
    end
end

MavenTools.update_test = update_buf

MavenTools.test = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            maven_importer.refresh_entry(v.item)
            break
        end
    end
end

MavenTools.open_pom_file = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            -- local mods = v.item.modules
            -- if mods == nil then
            --     return
            -- end
            --
            -- for _, x in pairs(mods.children) do
            --     print(tostring(x.info))
            -- end
            --
            local file = maven_importer.mavenInfoPomFile[tostring(v.item.info)] or v.item.file

            if file ~= nil then
                local file_buf = utils.get_file_buffer(file)

                if file_buf == nil then
                    -- vim.api.nvim_set_current_win(main_win)

                    vim.api.nvim_win_call(main_win, function()
                        vim.api.nvim_command("edit " .. file)
                    end)
                else
                    -- vim.api.nvim_set_current_win(main_win)
                    vim.api.nvim_win_set_buf(main_win, file_buf)
                end
            end

            -- vim.api.nvim_buf_call(runner_buf_id, function()
            --     vim.cmd("normal! G")
            -- end)
            --
            -- if file_buf == nil then
            --     vim.api.nvim_set_current_win(main_win_id)
            --     vim.api.nvim_command("edit " .. file)
            -- else
            --     vim.api.nvim_set_current_win(main_win_id)
            --     vim.api.nvim_win_set_buf(main_win_id, file_buf)
            -- end
            --
            -- vim.api.nvim_win_set_buf(main_win)
            -- vim.api.nvim_command("edit " .. maven_importer.Maven_Info_Pom_File[tostring(v.item.info)])
            -- print(tostring(v.item.info), maven_importer.Maven_Info_Pom_File[tostring(v.item.info)])
            break
        end
    end
end

MavenTools.show_error = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            if v.item.file ~= nil then
                print(maven_importer.pomFileError[v.item.file])
            end
            break
        end
    end
end

MavenTools.show_effective_pom = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            MavenToolsImporter.effective_pom(v.item, function(effective_pom)
                local buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(effective_pom, "\n"))
                vim.api.nvim_win_set_buf(main_win, buf)
                vim.api.nvim_buf_call(buf, function()
                    vim.api.nvim_command("setfiletype xml")
                end)
            end)
            break
        end
    end
end

function MavenTools.toggle_()
    require("maven-tools.ui.main"):start()
end

local function toggle()
    require("maven-tools.ui.main"):start()
end

local function debug()
    newImporter.update(vim.uv.cwd(), nil)
end

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
                vim.api.nvim_create_user_command("MavenToolsToggle", toggle, {})
                vim.api.nvim_create_user_command("MavenToolsDebug", debug, {})
                vim.api.nvim_create_user_command("MavenToolsRun", 'lua require("maven-tools.ui.main").run(0)', {})
                vim.api.nvim_create_user_command("MavenToolsAddDependency", 'lua require("maven-tools.ui.main").add_dependency(0)', {})
            end)
        end)
    end)

    return MavenTools
end

return MavenTools
