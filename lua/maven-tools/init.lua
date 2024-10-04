M = {}

local prefix = "maven-tools."

---@type Config
local config = require(prefix .. "config.config")

---@type Utils
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


---@type Maven_Importer
local maven_importer = require(prefix .. "maven.importer")

local main_win = vim.api.nvim_get_current_win()


M.show_win = function()
    if maven_win == nil and maven_buf ~= nil then
        maven_win = create_tree_window(maven_buf)
    end
end


M.update_test = update_buf

M.test = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            maven_importer.refresh_entry(v.item)
            break
        end
    end
end

M.open_pom_file = function()
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
            local file = maven_importer.Maven_Info_Pom_File[tostring(v.item.info)] or v.item.file

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

M.show_error = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            if v.item.file ~= nil then
                print(maven_importer.Pom_File_Error[v.item.file])
            end
            break
        end
    end
end

M.show_effective_pom = function()
    local line = vim.fn.line(".")

    for _, v in ipairs(line_roots) do
        if line >= v.first and line <= v.last then
            Importer.effective_pom(v.item, function(effective_pom)
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

function M.filter()
    filter = vim.fn.input("Filter: ")
    update_buf()
end


-- Function to toggle expand/collapse
-- function M.toggle_item_at(index)
--     tree[index].expanded = not tree[index].expanded
--     -- Update the tree buffer content
--     local buf = create_tree_buffer()
--     -- Get the current window and update its buffer
--     local win = vim.api.nvim_get_current_win()
--     vim.api.nvim_win_set_buf(win, buf)
--
--     vim.api.nvim_command('syntax region @label start="" end=" "')
--     vim.api.nvim_command('syntax region @label start="" end="$"')
-- end
--
--
local function toggle()
    main_win = vim.api.nvim_get_current_win()
    -- maven_buf = create_tree_buffer()
    -- maven_win = create_tree_window(maven_buf)
    -- maven_importer.make_tree_mp(update_buf)
    -- maven_importer.process_pom_files("/home/helmy/ssd/1tbnvmebackup/work/atoms-software-suite", update_buf)

    -- maven_importer.process_pom_files(vim.loop.cwd(), update_buf)
    require("maven-tools.ui.main"):start()

    

    vim.api.nvim_create_user_command("MavenShow", M.show_win, {}) 
end

function M.setup()
    vim.api.nvim_create_user_command("MavenToolsToggle", toggle, {})
end

return M
