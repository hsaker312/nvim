M = {}

M._offload_mp = function(res_path, proc_info)
    local module_name = proc_info.module_name
    local function_name = proc_info.function_name
    local arg = proc_info.arg
    local res = nil

    if type(module_name) == "string" and type(function_name) == "string" and type(arg) == "table" then
        pcall(function()
            res = require(module_name)[function_name](arg)
        end)
    end

    if res == nil then
        res = {}
    end
    pcall(function()
        local res_file = io.open(res_path, "w")

        if res_file then
            res_file:write(vim.fn.json_encode(res))
            res_file:close()
        end
    end)

    os.exit()
end

return M
