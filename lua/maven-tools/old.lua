---@type Array
Importer.tree = utils.Array()

---@type table<string,string[]>
local maven_modules = {}

---@type table<string,File_Index>
local pom_file_index = {}

---@type table<string,integer[]>
local pom_file_modules = {}

---@param pom_file string
---@param callback fun(Project_Info?):nil
local project_name = function(pom_file, callback)
    ---@class Project_Info
    ---@field name string
    ---@field error boolean

    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(pom_file, { 'help:evaluate "-Dexpression=project.name"' }),
        function(pipe_res)
            local proj_name = "error (" .. pom_file .. ")"
            local error = true

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
                    break
                end

                if not line:match("^%[") then
                    proj_name = line:gsub("\n", "")
                    error = false
                    break
                end
            end

            callback({ name = proj_name, error = error })
        end
    )
end

---comment
---@param index integer
---@param pom_file string
---@param callback fun(repo: string?)
---@return string?
local function get_repo(index, pom_file, callback)
    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(pom_file, {
            'help:evaluate "-Dexpression=project.repositories[' .. tostring(index) .. '].id"',
            'help:evaluate "-Dexpression=project.repositories[' .. tostring(index) .. '].url"',
        }),
        function(pipe_res)
            local count = 0
            local res = {}

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
                    break
                end

                if not line:match("^%[") then
                    table.insert(res, { line:gsub("\n", "") })
                    count = count + 1

                    if count >= 2 then
                        break
                    end
                end
            end

            if count >= 2 then
                callback(res[1][1] .. "(" .. res[2][1] .. ")")
            else
                callback()
            end
        end
    )
end

---@param index integer
---@param pom_file string
---@param callback fun(module:string?):nil
local function get_module(index, pom_file, callback)
    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(
            pom_file,
            { 'help:evaluate "-Dexpression=project.modules[' .. tostring(index) .. ']"' }
        ),
        function(pipe_res)
            ---@type string?
            local res = nil

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
                    break
                end

                if not line:match("^%[") then
                    res = line:gsub("\n", "")
                    break
                end
            end

            callback(res)
        end
    )
end

---@class Plugin_Info
---@field group_id string
---@field artifact_id string
---@field version string

---@param index integer
---@param pom_file string
---@param callback fun(info: Plugin_Info?):nil
local function plugin_info(index, pom_file, callback)
    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(pom_file, {
            'help:evaluate "-Dexpression=project.build.plugins[' .. tostring(index) .. '].groupId"',
            'help:evaluate "-Dexpression=project.build.plugins[' .. tostring(index) .. '].artifactId"',
            'help:evaluate "-Dexpression=project.build.plugins[' .. tostring(index) .. '].version"',
        }),
        ---@param pipe_res string
        function(pipe_res)
            ---@type string[][]
            local res = {}
            local count = 0

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
                    break
                end

                if not line:match("^%[") then
                    table.insert(res, { line:gsub("\n", "") })
                    count = count + 1

                    if count >= 3 then
                        break
                    end
                end
            end

            if count < 3 then
                callback(nil)
                return
            end

            callback({
                group_id = res[1][1],
                artifact_id = res[2][1],
                version = res[3][1],
            })
        end
    )
end

---@param index integer
---@param pom_file string
---@param callback fun(plugin: Plugin?):nil
local function get_plugin(index, pom_file, callback)
    ---@param callback_res Plugin_Info?
    plugin_info(index, pom_file, function(callback_res)
        if callback_res == nil then
            callback(nil)
            return
        end

        task_mgr:run(
            pom_file,
            maven_config.importer_pipe_cmd(pom_file, {
                "help:describe "
                    .. '"-DgroupId='
                    .. callback_res.group_id
                    .. '" "-DartifactId='
                    .. callback_res.artifact_id
                    .. '" "-Dversion='
                    .. callback_res.version
                    .. '"',
            }),
            ---@param pipe_res string
            ---@diagnostic disable-next-line: redefined-local
            function(pipe_res)
                ---@class Plugin
                ---@field goal string
                ---@field commands string[]
                local plugin = nil

                for line in pipe_res:gmatch("[^\n]*\n") do
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
    end)
end

---@param pom_file string
---@param callback fun(dependencies: string?):nil
local function get_dependencies(index, pom_file, callback)
    -- task_mgr:run(pom_file, maven_config.importer_pipe_cmd(pom_file, { "dependency:list" }), function(pipe_res)
    --     ---@type string[]
    --     local dependencies = {}
    --
    --     for line in pipe_res:gmatch("[^\n]*\n") do
    --         if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
    --             break
    --         else
    --             local dep, mod = line:match("([^%s]+)[%s]+%-%-[%s]+module[%s]+([^%s]+)")
    --
    --             if dep ~= nil then
    --                 local groupId, artifactId, _, version = dep:match("([^:]+):([^:]+):([^:]+):(%d[^:]+)")
    --                 local dependency = mod .. " (" .. groupId .. ":" .. artifactId .. ":" .. version .. ")"
    --
    --                 if version ~= nil then
    --                     table.insert(dependencies, dependency)
    --                 end
    --             end
    --         end
    --     end
    --
    --     callback(dependencies)
    -- end)
    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(pom_file, {
            'help:evaluate "-Dexpression=project.dependencies[' .. index .. '].groupId"',
            'help:evaluate "-Dexpression=project.dependencies[' .. index .. '].artifactId"',
            'help:evaluate "-Dexpression=project.dependencies[' .. index .. '].version"',
        }),
        function(pipe_res)
            ---@type string[][]
            local res = {}
            local count = 0

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
                    break
                end

                if not line:match("^%[") then
                    table.insert(res, { line:gsub("\n", "") })
                    count = count + 1

                    if count >= 3 then
                        break
                    end
                end
            end

            if count >= 3 then
                callback(res[1][1] .. ":" .. res[2][1] .. ":" .. res[3][1])
            else
                callback(nil)
            end
        end
    )
end

---comment
---@param pom_file string
---@return Tree_Entry
local function make_plugins_mp(pom_file)
    ---@type Tree_Entry
    local res = {
        text = "Plugins",
        icon = "󱧽 ",
        file = pom_file,
        expanded = false,
        children = {},
        callback = "0",
    }

    ---@param index integer
    local function plugin_at(index)
        get_plugin(index, pom_file, function(callback_res)
            if callback_res == nil then
                update_callback()
                return
            end

            ---@type Tree_Entry
            local item = {
                text = callback_res.goal,
                icon = " ",
                file = pom_file,
                expanded = false,
                children = {},
                callback = "0",
            }

            for _, command in ipairs(callback_res.commands) do
                local subitem = {
                    text = command[1],
                    icon = " ",
                    file = pom_file,
                    command = callback_res.goal .. ":" .. command[1],
                    expanded = false,
                    children = {},
                    callback = "1",
                }

                table.insert(item.children, subitem)
            end

            res.children[index + 1] = item

            -- update_callback()
            plugin_at(index + 4)
        end)
    end

    plugin_at(0)
    plugin_at(1)
    plugin_at(2)
    plugin_at(3)

    return res
end

---@param pom_file string
---@return Tree_Entry
local function make_dependencies_mp(pom_file)
    ---@type Tree_Entry
    local res = {
        text = "Dependencies",
        icon = " ",
        file = pom_file,
        expanded = false,
        children = {},
        callback = "0",
    }

    local function dep_at(index)
        get_dependencies(index, pom_file, function(dependency)
            if dependency == nil then
                update_callback()
                return
            end

            ---@type Tree_Entry
            local item = {
                text = dependency,
                icon = " ",
                file = pom_file,
                expanded = false,
                children = {},
                callback = "2",
            }

            res.children[index + 1] = item

            dep_at(index + 4)
        end)
    end

    dep_at(0)
    dep_at(1)
    dep_at(2)
    dep_at(3)

    return res
end

---comment
---@param pom_file string
---@return Tree_Entry
local function make_repositories_mp(pom_file)
    ---@type Tree_Entry
    local res = {
        text = "Repositories",
        icon = " ",
        file = pom_file,
        expanded = false,
        children = {},
        callback = "0",
    }

    local function repo_at(index)
        get_repo(index, pom_file, function(callback_res)
            if callback_res == nil then
                update_callback()
                return
            end

            repo_at(index + 2)

            ---@type Tree_Entry
            local item = {
                text = callback_res,
                icon = "󰳐 ",
                file = pom_file,
                callback = "2",
                expanded = false,
                children = {},
            }

            res.children[index + 1] = item
        end)
    end

    repo_at(0)
    repo_at(1)

    return res
end

---@param pom_file string
---@return nil
local function make_modules_mp(pom_file)
    ---@type string[]
    local res = {}

    maven_modules[pom_file] = res

    ---@param index integer
    local function module_at(index)
        get_module(index, pom_file, function(callback_res)
            if callback_res == nil then
                update_callback()
                return
            end

            module_at(index + 4)

            res[index + 1] = pom_file:gsub("pom.xml", "") .. callback_res .. "/pom.xml"
        end)
    end

    module_at(0)
    module_at(1)
    module_at(2)
    module_at(3)
end

---@param pom_file string
---@param is_module boolean?
---@return Tree_Entry
local function process_pom_file(pom_file, is_module)
    ---@type Tree_Entry
    local item = {
        text = "",
        icon = " ",
        file = pom_file,
        expanded = false,
        callback = "0",
        children = {},
    }

    ---@param callback_res Project_Info
    project_name(pom_file, function(callback_res)
        if callback_res.name == nil or callback_res.error == nil then
            update_callback()
            return
        end

        item.text = callback_res.name
        item.error = callback_res.error

        if item.error then
            task_mgr:mark_file_error(pom_file)
        end

        update_callback()
    end)

    if is_module then
        item.module = true
    else
        item.module = false
    end

    item.file = pom_file
    item.expanded = false
    item.callback = "0"
    item.modules = nil
    item.children = {
        make_lifecycle(pom_file),
        make_plugins_mp(pom_file),
        make_dependencies_mp(pom_file),
        make_repositories_mp(pom_file),
    }

    make_modules_mp(pom_file)

    pom_file_index[pom_file] = { index = Importer.tree:size() + 1, checksum = utils.file_checksum(pom_file) }

    return item
end

local function update_maven_modules()
    for pom_file, maven_module_files in pairs(maven_modules) do
        local project_index = pom_file_index[pom_file].index

        if project_index ~= nil then
            ---@type Tree_Entry
            local project = Importer.tree[project_index]

            ---@type Tree_Entry
            local item = {
                text = "Modules",
                icon = "󱧷 ",
                file = pom_file,
                expanded = false,
                children = {},
                callback = "0",
            }

            if maven_module_files[1] ~= nil then
                project.modules = item

                for i, maven_module in ipairs(maven_module_files) do
                    local submodule_index = nil

                    if pom_file_index[maven_module] ~= nil then
                        submodule_index = pom_file_index[maven_module].index
                    end

                    if submodule_index ~= nil then
                        local submodule = Importer.tree[submodule_index]
                        submodule.module = true

                        item.children[i] = submodule

                        if pom_file_modules[pom_file] ~= nil then
                            local index = nil

                            for j, value in ipairs(pom_file_modules[pom_file]) do
                                if value == submodule_index then
                                    index = j
                                    break
                                end
                            end

                            if index ~= nil then
                                table.remove(pom_file_modules[pom_file], index)
                            end
                        end
                    elseif
                        not config.recursive_pom_search or (pom_files ~= nil and pom_files:contains(maven_module))
                    then
                        local module_pom_file = io.open(maven_module, "r")

                        if module_pom_file then
                            module_pom_file:close()

                            Importer.tree:append(process_pom_file(maven_module))
                            Importer.tree[Importer.tree:size()].module = true
                        else
                            local root_dir = pom_file:gsub("pom.xml", ""):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

                            item.children[i] = {
                                text = maven_module:gsub(root_dir, ""):gsub("/pom.xml", "") .. "(module not found)",
                                icon = " ",
                                callback = "2",
                                expanded = false,
                                error = true,
                                children = {},
                            }
                        end
                    else
                        local root_dir = pom_file:gsub("pom.xml", ""):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

                        item.children[i] = {
                            text = maven_module:gsub(root_dir, ""):gsub("/pom.xml", "") .. "(module not found)",
                            icon = " ",
                            callback = "2",
                            expanded = false,
                            error = true,
                            children = {},
                        }
                    end
                end
            end
        end

        if pom_file_modules[pom_file] ~= nil then
            for _, value in ipairs(pom_file_modules[pom_file]) do
                Importer.tree[value].module = false
            end

            pom_file_modules[pom_file] = nil
        end
    end

    update_callback(1)

    local path = cwd .. "/" .. config.local_config_dir
    local success, _ = utils.create_directories(path)

    if success then
        local res_file = io.open(path .. "/cache.json", "w")

        if res_file then
            vim.schedule(function()
                res_file:write(vim.fn.json_encode({ files = pom_file_index, tree = Importer.tree:values() }))
                res_file:close()
            end)
        end
    end
end

local function process_pom_if_module(pom_file)
    task_mgr:run(
        pom_file,
        maven_config.importer_pipe_cmd(pom_file, { 'help:evaluate "-Dexpression=project.parent"' }),
        function(pipe_res)
            local is_module = false

            for line in pipe_res:gmatch("[^\n]*\n") do
                if line:match("null ") or line:match("invalid ") or line:match("ERROR") then
                    break
                end

                if line:match("^<") then
                    is_module = true
                    break
                end
            end

            if is_module then
                Importer.tree:append(process_pom_file(pom_file, true))
            else
                update_callback()
            end
        end
    )
end

---@param pom_file string
function Importer.refresh_pom(pom_file)
    if pom_file_index[pom_file] ~= nil and pom_file_index[pom_file].index ~= nil then
        ---@type Tree_Entry?
        local modules = Importer.tree[pom_file_index[pom_file].index].modules

        if modules ~= nil then
            ---@type integer[]
            local module_indices = {}

            for _, child in ipairs(modules.children) do
                if pom_file_index[child.file] ~= nil then
                    if pom_file_index[child.file].index ~= nil then
                        table.insert(module_indices, pom_file_index[child.file].index)
                    end
                end
            end

            pom_file_modules[pom_file] = module_indices
        end

        Importer.tree[pom_file_index[pom_file].index] = process_pom_file(pom_file)
    end
end

---@param callback function?
---@return nil
function Importer.make_tree_mp(callback)
    if callback ~= nil then
        update_callback = function(arg)
            if arg == nil then
                if task_mgr:idle() then
                    task_mgr:reset()

                    update_maven_modules()
                    return
                end
            end

            vim.schedule(callback)
        end
    end

    local res_file = io.open(cwd .. "/" .. config.local_config_dir .. "/cache.json", "r")

    ---@type Tree_Entry[]
    local cached_tree = nil

    ---@type table<string, File_Index>
    local cached_files = nil

    if res_file then
        local res_str = res_file:read("*a")
        res_file:close()
        local cache = vim.fn.json_decode(res_str)

        cached_tree = cache.tree
        cached_files = cache.files
    end

    pom_files = utils.find_pom_files(cwd)
    local main_project = true

    for _, pom_file in ipairs(pom_files) do
        local use_cache = false

        if cached_files ~= nil then
            if cached_files[pom_file] ~= nil then
                if
                    cached_files[pom_file].checksum ~= nil
                    and cached_files[pom_file].index ~= nil
                    and cached_files[pom_file].checksum == utils.file_checksum(pom_file)
                then
                    if cached_tree[cached_files[pom_file].index] ~= nil then
                        local item = cached_tree[cached_files[pom_file].index]
                        use_cache = item.module ~= nil
                            and item.text ~= nil
                            and item.icon ~= nil
                            and item.file ~= nil
                            and item.children ~= nil
                            and item.callback ~= nil
                    end
                end
            end
        end

        if config.multiproject or main_project then
            if use_cache then
                ---@diagnostic disable-next-line: need-check-nil
                Importer.tree:append(cached_tree[cached_files[pom_file].index])
                pom_file_index[pom_file] = { index = Importer.tree:size(), checksum = utils.file_checksum(pom_file) }
                Importer.tree[Importer.tree:size()].expanded = false

                update_callback(1)
            else
                Importer.tree:append(process_pom_file(pom_file))
            end

            main_project = false
        else
            if use_cache then
                ---@diagnostic disable-next-line: need-check-nil
                local entry = cached_tree[cached_files[pom_file].index]

                if entry.module then
                    Importer.tree:append(entry)
                    pom_file_index[pom_file] =
                        { index = Importer.tree:size(), checksum = utils.file_checksum(pom_file) }
                    Importer.tree[Importer.tree:size()].expanded = false

                    update_callback(1)
                end
            else
                process_pom_if_module(pom_file)
            end
        end
    end
end
