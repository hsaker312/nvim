---@class Runner
Runner = {}

local prefix = "maven-tools."

---@type Maven_Config
local maven_config = require(prefix .. "config.maven")

---@type integer?
local runner_win_id = nil

---@type integer?
local runner_buf_id = nil

---@type uv_process_t?
local runner_handle = nil

---@type integer[]
local autocmds = {}

local lines_count = 0

local baleia = require("baleia").setup({ log = "ERROR" })

local function create_buf()
    runner_buf_id = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_option_value("modifiable", true, {
        buf = runner_buf_id,
    })

    vim.api.nvim_set_option_value("buftype", "nofile", {
        buf = runner_buf_id,
    })

    vim.api.nvim_set_option_value("swapfile", false, {
        buf = runner_buf_id,
    })

    vim.api.nvim_set_option_value("bufhidden", "wipe", {
        buf = runner_buf_id,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "q", "<Cmd>quit<CR>", {
        noremap = true,
        silent = true,
    })
end

local function create_win()
    create_buf()

    if runner_buf_id ~= nil then
        local current_win = vim.api.nvim_get_current_win()
        -- local cursor = vim.api.nvim_win_get_cursor(current_win)

        runner_win_id = vim.api.nvim_open_win(runner_buf_id, true, {
            split = "below",
            win = -1,
            height = 10,
        })

        vim.api.nvim_set_current_win(current_win)
        -- vim.api.nvim_win_set_cursor(current_win, )

        vim.api.nvim_set_option_value("number", false, {
            win = runner_win_id,
        })

        vim.api.nvim_set_option_value("spell", false, {
            win = runner_win_id,
        })

        table.insert(
            autocmds,
            vim.api.nvim_create_autocmd("WinClosed", {
                callback = function(event)
                    if runner_win_id ~= nil then
                        if tonumber(event.match) == runner_win_id then
                            runner_win_id = nil
                            for _, autocmd in ipairs(autocmds) do
                                vim.api.nvim_del_autocmd(autocmd)
                            end
                            autocmds = {}
                        end
                    end
                end,
            })
        )
    end
end

local function is_buffer_scrolled_to_end(buffer_id)
    -- Get the total number of lines in the buffer
    local total_lines = vim.api.nvim_buf_line_count(buffer_id)

    -- Get the current window's cursor position (line, column)
    ---@diagnostic disable-next-line: param-type-mismatch
    local current_cursor_position = vim.api.nvim_win_get_cursor(runner_win_id)

    -- Get the number of visible lines in the current window
---@diagnostic disable-next-line: param-type-mismatch
    local visible_lines = vim.api.nvim_win_get_height(runner_win_id)

    -- Calculate the last visible line in the window
    local last_visible_line = current_cursor_position[1] + visible_lines - 1

    -- Check if the last visible line is greater than or equal to the total number of lines
    return last_visible_line >= total_lines
end

local function append_to_buffer(lines, count)
    if runner_buf_id == nil then
        return
    end

    vim.schedule(function()
        local scroll = is_buffer_scrolled_to_end(runner_buf_id)

        vim.api.nvim_set_option_value("modifiable", true, {
            buf = runner_buf_id,
        })
        --
        local lastline = vim.api.nvim_buf_line_count(runner_buf_id)

        baleia.buf_set_lines(runner_buf_id, lastline, lastline, true, lines)
        -- vim.api.nvim_buf_set_lines(runner_buf_id, lastline, lastline, true, lines)
        --
        vim.api.nvim_set_option_value("modifiable", false, {
            buf = runner_buf_id,
        })

        lines_count = lines_count + count

        if scroll then
            vim.api.nvim_buf_call(runner_buf_id, function()
                vim.cmd("normal! G")
            end)
        end
    end)
end

local current_command = ""
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_count = 10
local running = false
local success = false
local run_total_time = ""

local function real_time_notification()
    running = true
    local timer = vim.loop.new_timer()
    local counter = 1

    local function update_notification()
        if running then
            if counter > spinner_count then
                counter = 1
            end

            vim.api.nvim_echo({ { " " .. spinner[counter] .. " " .. current_command, "Normal" } }, false, {})
            counter = counter + 1
        else
            if success then
                vim.api.nvim_echo({ { "  " .. current_command .. ": done in " .. run_total_time, "DiagnosticOk" } }, false, {})
            else
                vim.api.nvim_echo({ { "  " .. current_command .. ": failed in " .. run_total_time, "Error" } }, false, {})
            end

            timer:stop()
            timer:close()
        end
    end

    -- Start the timer to update every 1000 milliseconds (1 second)
    timer:start(0, 100, vim.schedule_wrap(update_notification))

    -- Stop the timer when Neovim exits
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            timer:stop()
            timer:close()
        end,
    })
end

local msg_buf = ""

---@param entry Tree_Entry
function Runner.run(entry, pom_file)
    if entry.command == nil then
        return
    end

    if runner_handle ~= nil and not runner_handle:is_closing() then
        runner_handle:kill("sigterm")
    end
    --
    -- if runner_win_id ~= nil then
    --     for _, autocmd in ipairs(autocmds) do
    --         vim.api.nvim_del_autocmd(autocmd)
    --     end
    --     autocmds = {}
    --     vim.api.nvim_win_close(runner_win_id, true)
    -- end

    if runner_win_id == nil then
        create_win()
    else
        if runner_buf_id then
            vim.api.nvim_set_option_value("modifiable", true, {
                buf = runner_buf_id,
            })

            baleia.buf_set_lines(runner_buf_id, 0, -1, true, {})
            -- vim.api.nvim_buf_set_lines(runner_buf_id, 0, -1, true, {})
            lines_count = 0

            vim.api.nvim_set_option_value("modifiable", false, {
                buf = runner_buf_id,
            })
        end
    end

    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    local pipe_cmd = maven_config.runner_pipe_cmd(pom_file, { entry.command })
    current_command = entry.command

    real_time_notification()

    runner_handle = vim.loop.spawn(pipe_cmd.cmd, {
        args = pipe_cmd.args,
        stdio = { nil, stdout, stderr },
    }, function()
        running = false
        stdout:close()
        stderr:close()

        if runner_handle ~= nil then
            runner_handle:close()
            runner_handle = nil
        end
    end)

    local function process_data(err, data)
        if data then
            local lines = {}
            local data_lines_count = 0
            data = data:gsub("[\r\n|\n\r]", "\n"):gsub("\r", ""):gsub("\27%[m", "\27%[0m")
            msg_buf = msg_buf .. data

            if msg_buf:sub(#msg_buf, #msg_buf) == "\n" then
                for line in data:gmatch("[^\n]+") do
                    ---@cast line string
                    if line ~= "" then
                        if line:match("BUILD FAILURE") or line:match("ERROR") then
                            success = false
                        elseif line:match("BUILD SUCCESS") then
                            success = true
                        elseif line:match("Total time:") then
                            run_total_time = line:gsub(".+Total time:", ""):gsub("%s", "")
                        end

                        table.insert(lines, line)

                        data_lines_count = data_lines_count + 1
                    end
                end
                append_to_buffer(lines, data_lines_count)
                msg_buf = ""
            end
        end

        if err then
            success = false
        end
    end

    vim.loop.read_start(stdout, process_data)
    vim.loop.read_start(stderr, process_data)
end

return Runner
