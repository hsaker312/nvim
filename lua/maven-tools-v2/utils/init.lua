---@class MavenUtils
MavenToolsUtils = {}

local prefix = "maven-tools-v2."

---@type MavenToolsConfig
local config = require(prefix .. "config.config")

---@generic T
---@param t1 T[]
---@param t2 T[]
---@return T[]
function MavenToolsUtils.array_join(t1, t2)
    local res = {}

    for _, v in ipairs(t1) do
        table.insert(res, v)
    end

    for _, v in ipairs(t2) do
        table.insert(res, v)
    end

    return res
end

---@param str string
function MavenToolsUtils.escape_match_specials(str)
    return str:gsub("([()%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

function MavenToolsUtils.table_join(t1, t2)
    local res = {}

    for k, v in pairs(t1) do
        res[k] = v
    end

    for k, v in pairs(t2) do
        res[k] = v
    end

    return res
end

---@param file string
---@return integer?
function MavenToolsUtils.get_file_buffer(file)
    local buffers = vim.api.nvim_list_bufs()

    for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
            if vim.api.nvim_buf_get_name(buf) == file then
                return buf
            end
        end
    end
end

---@return integer|nil
function MavenToolsUtils.get_editor_window()
    local windows = vim.api.nvim_tabpage_list_wins(0)

    for _, win in ipairs(windows) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buf_name = vim.api.nvim_buf_get_name(buf)

        if buf_name ~= nil and buf_name ~= "" then
            if buf_name:match("[%[|%]]") == nil then
                return win
            end
        end
    end

    return nil
end

---@param file string
function MavenToolsUtils.open_file(file)
    if file ~= nil then
        local file_buf = MavenToolsUtils.get_file_buffer(file)
        local editor_win = MavenToolsUtils.get_editor_window()

        if editor_win ~= nil then
            if file_buf == nil then
                vim.api.nvim_win_call(editor_win, function()
                    vim.api.nvim_command("edit " .. file)
                end)
            else
                vim.api.nvim_win_set_buf(editor_win, file_buf)
            end
        end
    end
end

---@param ary table|nil
---@return Array
function MavenToolsUtils.Array(ary)
    ---@class Array
    ---@field private _size integer
    ---@field private _values any[]
    local array = {
        _size = 0,
        _values = {},
    }

    ---@param value any
    ---@return Array
    function array:append(value)
        self._size = self._size + 1
        table.insert(self._values, value)
        return self
    end

    ---@param index integer
    ---@param value any
    ---@return nil
    function array:insert(index, value)
        local values = {}

        if index >= 2 then
            if index > (self._size + 1) then
                index = self._size + 1
            end

            for i = 1, index - 1, 1 do
                table.insert(values, self._values[i])
            end
        end

        table.insert(values, value)

        if index < 0 then
            index = 1
        end

        if self._size >= index then
            for i = index, self._size, 1 do
                table.insert(values, self._values[i])
            end
        end

        self._size = self._size + 1
        self._values = values
    end

    ---@param value any
    ---@return integer?
    function array:find(value)
        for i = 1, self._size, 1 do
            if self._values[i] == value then
                return i
            end
        end
    end

    ---@param value any
    ---@return boolean
    function array:contains(value)
        return self:find(value) ~= nil
    end

    ---@param index integer?
    ---@return nil
    function array:remove(index)
        if index ~= nil then
            table.remove(self._values, index)
            self._size = self._size - 1
        end
    end

    ---@param value any
    ---@return nil
    function array:remove_value(value)
        self:remove(self:find(value))
    end

    ---@return integer
    function array:size()
        return self._size
    end

    ---@return boolean
    function array:empty()
        return self._size == 0
    end

    ---@return any[]
    function array:values()
        return self._values
    end

    setmetatable(array, {
        __index = function(self, index)
            return self._values[index]
        end,
        __newindex = nil,
        __pairs = function(self)
            return pairs(self._values)
        end,
        __ipairs = function(self)
            return ipairs(self._values)
        end,
        __type = "Array",
    })

    if ary ~= nil then
        for _, v in ipairs(ary) do
            array:append(v)
        end
    end

    return array
end

local crc32_table = {}

for i = 0, 255 do
    local crc = i
    for _ = 1, 8 do
        if bit.band(crc, 1) ~= 0 then
            crc = bit.bxor(bit.rshift(crc, 1), 0xEDB88320)
        else
            crc = bit.rshift(crc, 1)
        end
    end
    crc32_table[i] = crc
end

---@param s string
---@return integer
local function crc32(s)
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        local byte = string.byte(s, i)
        crc = bit.bxor(crc32_table[bit.band(bit.bxor(crc, byte), 0xFF)], bit.rshift(crc, 8))
    end
    return bit.band(bit.bnot(crc), 0xFFFFFFFF)
end

---@param str string
---@return string
function MavenToolsUtils.str_checksum(str)
    return string.format("%08X", crc32(str))
end

---@param filepath string
---@return string?
MavenToolsUtils.file_checksum = function(filepath)
    local file = io.open(filepath, "rb")

    if not file then
        return nil
    end

    local content = file:read("*all")
    file:close()

    return string.format("%08X", crc32(content))
end

---@param path string
---@return boolean
MavenToolsUtils.create_directories = function(path)
    local success, _ = pcall(vim.fn.mkdir, path, "p")
    return success
end

function MavenToolsUtils.flatten_map(tbl)
    local result = {}

    local function traverse(subtable, currentKey)
        for key, value in pairs(subtable) do
            local newKey = ""

            if currentKey == "" then
                newKey = key
            else
                newKey = currentKey .. "." .. key
            end

            if type(value) == "table" then
                traverse(value, newKey)
            else
                result[newKey] = value
            end
        end
    end

    traverse(tbl, "")

    return result
end

---@param path string
---@return Path
function MavenToolsUtils.Path(path)
    assert(type(path) == "string", "The path argument must be a string!")

    ---@class Path
    ---@field str string
    ---@field len integer
    local obj = {}

    path = vim.fs.normalize(path)

    obj.str = path:gsub("\\", "/")
    obj.len = #obj.str
    if obj.str:sub(obj.len, obj.len) == "/" then
        obj.str = obj.str:sub(1, obj.len - 1)
        obj.len = obj.len - 1
    end

    ---@param otherPath string|Path
    ---@return Path
    function obj:join(otherPath)
        local is_other_path = type(otherPath) == "table" and getmetatable(otherPath) and getmetatable(otherPath).__type == "Path"
        assert(
            type(otherPath) == "string" or is_other_path,
            "Path:join argument must be a string or a Path!"
        )

        if type(otherPath) == "string" then
            if otherPath:sub(1, 1) == "/" then
                return require(prefix .. "utils").Path(self.str .. otherPath)
            else
                return require(prefix .. "utils").Path(self.str .. "/" .. otherPath)
            end
        elseif is_other_path then
            if otherPath.str:sub(1, 1) == "/" then
                return require(prefix .. "utils").Path(self.str .. otherPath.str)
            else
                return require(prefix .. "utils").Path(self.str .. "/" .. otherPath.str)
            end
        else
            return require(prefix .. "utils").Path("")
        end
    end

    ---@return boolean
    function obj:is_directory()
        local stat = vim.uv.fs_stat(self.str)
        return stat ~= nil and stat.type == "directory"
    end

    ---@return boolean
    function obj:is_file()
        local stat = vim.uv.fs_stat(self.str)
        return stat ~= nil and stat.type == "file"
    end

    ---@return Array?
    function obj:readdir()
        if self:is_directory() then
            local files = vim.fn.readdir(self.str)
            local res = require(prefix .. "utils").Array()

            for _, file in ipairs(files) do
                if file ~= "." and file ~= ".." then
                    res:append(self:join(file))
                end
            end

            return res
        end
    end

    ---@return string?
    function obj:filename()
        if self:is_file() then
            return vim.fn.fnamemodify(self.str, ":t")
        end
    end

    ---@return Path?
    function obj:dirname()
        return require(prefix .. "utils").Path(vim.fn.fnamemodify(self.str, ":h"))
    end

    ---@return string?
    function obj:checksum()
        if self:is_file() then
            return MavenToolsUtils.file_checksum(self.str)
        end
    end

    ---@return boolean
    function obj:create_dir()
        if not self:is_file() then
            return MavenToolsUtils.create_directories(self.str)
        end

        return false
    end

    setmetatable(obj, {
        __tostring = function(self)
            return self.str
        end,
        __concat = function(t1, t2)
            local is_t1_path = type(t1) == "table" and getmetatable(t1) and getmetatable(t1).__type == "Path"
            local is_t2_path = type(t2) == "table" and getmetatable(t2) and getmetatable(t2).__type == "Path"
            if is_t1_path and is_t2_path then
                return t1.str .. t2.str
            elseif is_t1_path then
                return t1.str .. t2
            else
                return t1 .. t2.str
            end
        end,
        __type = "Path",
    })

    return obj
end

---@param path string
---@return string[]
function MavenToolsUtils.list_java_files(path)
    local javaFiles = {}

    local function scan_directory(dir)
        local req = vim.uv.fs_scandir(dir)

        if req then
            while true do
                local entry = vim.uv.fs_scandir_next(req)
                if not entry then
                    break
                end

                local fullPath = MavenToolsUtils.Path(dir):join(entry).str
                local stat = vim.uv.fs_stat(fullPath)

                if stat and stat.type == "directory" then
                    local pomCheck = vim.uv.fs_stat(fullPath .. "/pom.xml")

                    if not pomCheck then
                        scan_directory(fullPath)
                    end
                elseif entry:match("%.java$") then
                    table.insert(javaFiles, fullPath)
                end
            end
        end
    end

    scan_directory(path)

    return javaFiles
end

---@return Queue
function MavenToolsUtils.Queue()
    ---@class Queue
    local queue = {}

    queue.first = 0
    queue.last = -1
    queue.values = {}

    ---@param value any
    ---@return nil
    function queue:push(value)
        local last = self.last + 1
        self.last = last
        self.values[last] = value
    end

    ---@return any
    function queue:pop()
        local first = self.first

        if first > self.last then
            return nil
        end

        local value = self.values[first]
        self.values[first] = nil
        self.first = first + 1

        return value
    end

    setmetatable(queue, {
        __type = "Queue",
    })

    return queue
end

---@param file string
---@return boolean
function MavenToolsUtils.is_ignored(file)
    for _, ignore_file in ipairs(config.ignoreFiles) do
        if tostring(file):match(ignore_file) then
            return true
        end
    end

    return false
end

---@param directory string|Path
---@return Array?
MavenToolsUtils.find_pom_files = function(directory)
    local is_directory_path = type(directory) == "table" and getmetatable(directory) and getmetatable(directory).__type == "Path"
    ---@type Array
    local pom_files = require(prefix .. "utils").Array()
    ---@type Queue
    local dirs = require(prefix .. "utils").Queue()

    if type(directory) == "string" then
        directory = require(prefix .. "utils").Path(directory)
    elseif not is_directory_path then
        return
    end

    ---@param dir Path
    ---@return nil
    local function search_pom_files(dir)
        local files = dir:readdir()

        if files == nil then
            return
        end

        for _, file in ipairs(files:values()) do
            if file:filename() == "pom.xml" and not MavenToolsUtils.is_ignored(file) then
                pom_files:append(tostring(file))
            elseif config.recursivePomSearch and file:is_directory() then
                dirs:push(file)
            end
        end
    end

    search_pom_files(directory)

    if config.multiproject or pom_files:size() > 0 then
        ---@type Path?
        local next_dir = dirs:pop()

        while next_dir ~= nil do
            search_pom_files(next_dir)
            next_dir = dirs:pop()
        end
    end

    return pom_files
end

function MavenToolsUtils.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[require(prefix .. "utils").deepcopy(orig_key)] = require(prefix .. "utils").deepcopy(orig_value)
        end
        setmetatable(copy, require(prefix .. "utils").deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

---@param module_name string
---@param function_name string
---@param arg table
---@return Proc_Info
function MavenToolsUtils.Proc_Info(module_name, function_name, arg)
    ---@class Proc_Info
    local proc_info = {}

    proc_info.module_name = module_name
    proc_info.function_name = function_name
    proc_info.arg = arg

    setmetatable(proc_info, {
        __type = "Proc_Info",
    })

    return proc_info
end

---@return Task_Mgr
function MavenToolsUtils.Task_Mgr()
    ---@class Running_Task
    ---@field handle uv_process_t?
    ---@field stdout uv_pipe_t?
    ---@field stderr uv_pipe_t?

    ---@class Task_Mgr
    local task_manager = {}

    local task_queue = require(prefix .. "utils").Queue()
    local max_number_of_running_tasks = config.maxParallelJobs
    local number_of_running_tasks = 0
    local number_of_done_tasks = 0
    local total_number_of_tasks = 0
    local running_tasks = {}

    ---@type fun():nil|nil
    local on_idle = nil

    ---@return boolean
    function task_manager:idle()
        return number_of_running_tasks == 0
    end

    ---@return nil
    function task_manager:reset()
        total_number_of_tasks = 0
        number_of_done_tasks = 0
    end

    ---@return number
    function task_manager:progress()
        if total_number_of_tasks > 0 then
            return (number_of_done_tasks / total_number_of_tasks) * 100
        else
            return 0
        end
    end

    ---@param callback fun():nil
    function task_manager:set_on_idle_callback(callback)
        on_idle = callback
    end

    function task_manager:trigger_idle_callback()
        local handle

        handle = vim.uv.new_async(function()
            if type(on_idle) == "function" then
                on_idle()
            end

            if handle ~= nil then
                handle:close()
            end
        end)

        if handle ~= nil then
            handle:send()
        end
    end

    function task_manager:trigger_idle_callback_if_idle()
        if self:idle() then
            self:trigger_idle_callback()
        end
    end

    ---@param pipe_cmd PipeCmd
    ---@param callback fun(msg: string):nil
    ---@return nil
    function task_manager:run(pipe_cmd, callback)
        local task_number = total_number_of_tasks
        total_number_of_tasks = total_number_of_tasks + 1

        ---@class Task_Info
        local task = {
            task_number = task_number,
            pipe_cmd = pipe_cmd,
            callback = callback,
        }

        if number_of_running_tasks < max_number_of_running_tasks then
            number_of_running_tasks = number_of_running_tasks + 1
        else
            task_queue:push(task)
            return
        end

        ---@param task_info Task_Info
        ---@return nil
        local function invoke_task(task_info)
            local buffer = ""

            running_tasks[task_info.task_number] = { stdout = vim.uv.new_pipe(false), stderr = vim.uv.new_pipe(false) }

            running_tasks[task_info.task_number].handle = vim.uv.spawn(task_info.pipe_cmd.cmd, {
                args = task_info.pipe_cmd.args,
                stdio = {
                    nil,
                    running_tasks[task_info.task_number].stdout,
                    running_tasks[task_info.task_number].stderr,
                },
            }, function()
                running_tasks[task_info.task_number].handle:close()
                running_tasks[task_info.task_number].stdout:close()
                running_tasks[task_info.task_number].stderr:close()
                running_tasks[task_info.task_number] = nil

                ---@type Task_Info
                local next_task = task_queue:pop()

                if next_task ~= nil then
                    invoke_task(next_task)
                else
                    number_of_running_tasks = number_of_running_tasks - 1
                end

                number_of_done_tasks = number_of_done_tasks + 1
                task_info.callback(buffer)

                if number_of_running_tasks == 0 then
                    if type(on_idle) == "function" then
                        on_idle()
                    end
                end
            end)

            vim.uv.read_start(running_tasks[task_info.task_number].stdout, function(_, data)
                if data then
                    buffer = buffer .. data:gsub("[\1-\9\11-\31\127]", "")
                end
            end)

            vim.uv.read_start(running_tasks[task_info.task_number].stderr, function(_, data)
                if data then
                    buffer = buffer .. data:gsub("[\1-\9\11-\31\127]", "")
                end
            end)
        end

        invoke_task(task)
    end

    ---@param file string
    ---@param callback fun(lines: string):nil
    ---@param lineCount integer|nil
    function task_manager:readFile(file, callback, lineCount)
        local f = io.open(file, "r")
        if not f then
            vim.schedule(function() callback("") end)
            return
        end
        local lines = {}
        if type(lineCount) == "number" then
            for _ = 1, lineCount do
                local line = f:read("*l")
                if not line then break end
                table.insert(lines, line)
            end
        else
            lines = { f:read("*a") }
        end
        f:close()
        local content = table.concat(lines, "\n")
        vim.schedule(function() callback(content) end)
    end

    setmetatable(task_manager, {
        __type = "Task_Manager",
    })

    return task_manager
end

return MavenToolsUtils
