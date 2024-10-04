---@class Utils
M = {}

local prefix = "maven-tools."

---@type Config
local config = require(prefix .. "config.config")

local gpairs = pairs

_G.pairs = function(t)
    if getmetatable(t) ~= nil and getmetatable(t).__pairs ~= nil then
        return getmetatable(t).__pairs(t)
    else
        return gpairs(t)
    end
end

local gipairs = ipairs

_G.ipairs = function(t)
    if getmetatable(t) ~= nil and getmetatable(t).__ipairs ~= nil then
        return getmetatable(t).__ipairs(t)
    else
        return gipairs(t)
    end
end

local gtype = type

---@param v any
---@return "nil"|"number"|"string"|"boolean"|"table"|"function"|"thread"|"userdata"|"Array"
_G.type = function(v)
    if getmetatable(v) ~= nil and getmetatable(v).__type ~= nil then
        return getmetatable(v).__type(v)
    else
        return gtype(v)
    end
end

---@generic T
---@param t1 T[]
---@param t2 T[]
---@return T[]
function M.array_join(t1, t2)
    local res = {}

    for _, v in ipairs(t1) do
        table.insert(res, v)
    end

    for _, v in ipairs(t2) do
        table.insert(res, v)
    end

    return res
end

function M.table_join(t1, t2)
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
function M.get_file_buffer(file)
    local buffers = vim.api.nvim_list_bufs() -- Get a list of all buffer numbers

    for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
            if vim.api.nvim_buf_get_name(buf) == file then
                return buf
            end
        end
    end
end

---@return integer|nil
function M.get_editor_window()
    local windows = vim.api.nvim_tabpage_list_wins(0) -- Get all windows in the current tab page

    for _, win in ipairs(windows) do
        local buf = vim.api.nvim_win_get_buf(win) -- Get the buffer associated with the window
        local buf_name = vim.api.nvim_buf_get_name(buf) -- Get the buffer's name

        if buf_name ~= nil and buf_name ~= "" then
            if buf_name:match("[%[|%]]") == nil then
                return win
            end
        end
    end

    return nil
end


---@param ary table|nil
--- @return Array
function M.Array(ary)
    ---@class Array
    ---@field private _size integer
    ---@field private _values any[]
    local array = {
        _size = 0,
        _values = {},
    }

    --- @param value any
    --- @return Array
    function array:append(value)
        self._size = self._size + 1
        table.insert(self._values, value)
        return self
    end

    --- @param index integer
    --- @param value any
    --- @return nil
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

    --- @param value any
    --- @return integer?
    function array:find(value)
        for i = 1, self._size, 1 do
            if self._values[i] == value then
                return i
            end
        end
    end

    --- @param value any
    --- @return boolean
    function array:contains(value)
        return self:find(value) ~= nil
    end

    --- @param index integer?
    --- @return nil
    function array:remove(index)
        if index ~= nil then
            table.remove(self._values, index)
            self._size = self._size - 1
        end
    end

    --- @param value any
    --- @return nil
    function array:remove_value(value)
        self:remove(self:find(value))
    end
    ---
    --- @return integer
    function array:size()
        return self._size
    end

    --- @return boolean
    function array:empty()
        return self._size == 0
    end

    --- @return any[]
    function array:values()
        return self._values
    end

    setmetatable(array, {
        ---@param self Array
        ---@param index integer
        ---@return any
        __index = function(self, index)
            ---@diagnostic disable-next-line: invisible
            return self._values[index]
        end,
        __newindex = nil,
        __pairs = function(self)
            return gpairs(self._values)
        end,
        __ipairs = function(self)
            return gipairs(self._values)
        end,
        __type = function()
            return "Array"
        end,
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

--- @param s string
--- @return integer
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
function M.str_checksum(str)
    return string.format("%08X", crc32(str))
end

--- @param filepath string
--- @return string?
M.file_checksum = function(filepath)
    local file = io.open(filepath, "rb")

    if not file then
        return nil
    end

    local content = file:read("*all")
    file:close()

    return string.format("%08X", crc32(content))
end

--- @param path string
--- @return boolean
M.create_directories = function(path)
    -- Normalize the path to ensure it does not end with a '/'
    local normalized_path = path:gsub("/$", "")

    -- Split the path into individual directories
    local current_path = "/"
    if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
        current_path = normalized_path:match("^%s*.:/")
        if current_path then
            normalized_path = normalized_path:gsub(current_path, "")
        else
            return false
        end
    end

    for dir in string.gmatch(normalized_path, "([^/]+)") do
        current_path = current_path .. dir .. "/"

        -- Check if the directory exists
        local ok, _, code = os.rename(current_path, current_path)

        if not ok and code ~= 13 then
            -- Create the directory if it doesn't exist
            local success = vim.uv.fs_mkdir(current_path, 493) -- 493 is octal for 0755

            if not success then
                return false
            end
        end
    end

    return true
end

M.create_directories("c:/users/saker.helmy/test/tset")

--- @param path? string
--- @return Path?
function M.Path(path)
    --- @class Path
    local obj = {}

    if path ~= nil and type(path) == "string" then
        --- @type string
        obj.str = path:gsub("\\", "/")
    else
        return
    end

    --- @param self Path
    --- @param otherPath string|Path
    --- @return Path?
    function obj.join(self, otherPath)
        if type(otherPath) == "string" then
            return self:join(require(prefix .. "utils").Path(otherPath))
        elseif type(otherPath) == "Path" then
            if self.str:sub(#self.str, #self.str) == "/" then
                return require(prefix .. "utils").Path(self.str .. otherPath.str)
            else
                return require(prefix .. "utils").Path(self.str .. "/" .. otherPath.str)
            end
        end
    end

    --- @param self Path
    --- @return boolean
    function obj.is_directory(self)
        local stat = vim.uv.fs_stat(self.str)
        return stat ~= nil and stat.type == "directory"
    end

    --- @param self Path
    --- @return boolean
    function obj.is_file(self)
        local stat = vim.uv.fs_stat(self.str)
        return stat ~= nil and stat.type == "file"
    end

    --- @param self Path
    --- @return Array?
    function obj.readdir(self)
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

    --- @param self Path
    --- @return string?
    function obj.filename(self)
        if self:is_file() then
            return vim.fn.fnamemodify(self.str, ":t")
        end
    end

    --- @param self Path
    --- @return Path?
    function obj.dirname(self)
        if self:is_file() then
            return require(prefix .. "utils").Path(vim.fn.fnamemodify(self.str, ":h"))
        end
    end

    --- @param self Path
    --- @return string?
    function obj.checksum(self)
        if self:is_file() then
            return M.file_checksum(self.str)
        end
    end

    --- @param self Path
    --- @return boolean
    function obj.create_dir(self)
        if not self:is_file() then
            return M.create_directories(self.str)
        end

        return false
    end

    setmetatable(obj, {
        __tostring = function(self)
            return self.str
        end,
        ---@param t1 Path|string
        ---@param t2 Path|string
        ---@return string
        __concat = function(t1, t2)
            if type(t1) == "Path" and type(t2) == "Path" then
                return t1.str .. t2.str
            elseif type(t1) == "Path" then
                return t1.str .. t2
            else
                return t1 .. t2.str
            end
        end,
        __type = function()
            return "Path"
        end,
    })

    return obj
end

--- @return Queue
function M.Queue()
    --- @class Queue
    local queue = {}

    --- @type integer
    queue.first = 0
    --- @type integer
    queue.last = -1
    --- @type any[]
    queue.values = {}

    --- @param self Queue
    --- @return nil
    function queue.push(self, value)
        local last = self.last + 1
        self.last = last
        self.values[last] = value
    end

    --- @param self Queue
    --- @return any
    function queue.pop(self)
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
        __type = function()
            return "Queue"
        end,
    })

    return queue
end

-- local path1 = M.Path("/home/helmy")
-- print(type(path1))
-- -- print(M.Path("C:\\users\\helmy").str)
-- for k, v in pairs(path1:readdir()) do
--     print(v:dirname())
-- end

local function is_ignored(file)
    for _, ignore_file in ipairs(Config.ignore_files) do
        if tostring(file):match(ignore_file) then
            return true
        end
    end

    return false
end

--- @param directory string|Path
--- @return Array?
M.find_pom_files = function(directory)
    ---@type Array
    local pom_files = require(prefix .. "utils").Array()
    ---@type Queue
    local dirs = require(prefix .. "utils").Queue()

    if type(directory) == "string" then
        directory = require(prefix .. "utils").Path(directory)
    elseif type(directory) ~= "Path" then
        return
    end

    --- @param dir Path
    --- @return nil
    local function search_pom_files(dir)
        local files = dir:readdir()

        if files == nil then
            return
        end

        for _, file in ipairs(files) do
            if file:filename() == "pom.xml" and not is_ignored(file) then
                pom_files:append(tostring(file))
            elseif config.recursive_pom_search and file:is_directory() then
                dirs:push(file)
            end
        end
    end

    search_pom_files(directory)

    if config.multiproject or pom_files:size() > 0 then
        --- @type Path?
        local next_dir = dirs:pop()

        while next_dir ~= nil do
            search_pom_files(next_dir)
            next_dir = dirs:pop()
        end
    end

    return pom_files
end

function M.deepcopy(orig)
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

--- @param module_name string
--- @param function_name string
--- @param arg table
--- @return Proc_Info
function M.Proc_Info(module_name, function_name, arg)
    --- @class Proc_Info
    local proc_info = {}

    proc_info.module_name = module_name
    proc_info.function_name = function_name
    proc_info.arg = arg

    setmetatable(proc_info, {
        __type = function()
            return "Proc_Info"
        end,
    })

    return proc_info
end

--- @return Task_Mgr
function M.Task_Mgr()
    --- @class Running_Task
    --- @field handle uv_process_t?
    --- @field stdout uv_pipe_t?
    --- @field stderr uv_pipe_t?

    --- @class Task_Mgr
    local task_manager = {}

    local task_queue = require(prefix .. "utils").Queue()
    --- @type integer
    local max_number_of_running_tasks = config.max_parallel_jobs
    --- @type integer
    local number_of_running_tasks = 0
    --- @type integer
    local number_of_done_tasks = 0
    --- @type integer
    local total_number_of_tasks = 0
    --- @type Running_Task[]
    local running_tasks = {}

    ---@type fun():nil|nil
    local on_idle = nil

    --- @return boolean
    function task_manager.idle(_)
        return number_of_running_tasks == 0
    end

    --- @return nil
    function task_manager.reset(_)
        total_number_of_tasks = 0
        number_of_done_tasks = 0
    end

    --- @return number
    function task_manager.progress(_)
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
        if type(on_idle) == "function" then
            on_idle()
        end
    end

    ---@param pom_file string
    ---@param pipe_cmd Pipe_Cmd
    ---@param callback fun(msg: string):nil
    ---@return nil
    function task_manager:run(pom_file, pipe_cmd, callback)
        local task_number = total_number_of_tasks
        total_number_of_tasks = total_number_of_tasks + 1

        ---@class Task_Info
        local task = {
            pom_file = pom_file,
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

                --- @type Task_Info
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

    setmetatable(task_manager, {
        __type = function()
            return "Task_Manager"
        end,
    })

    return task_manager
end

return M
