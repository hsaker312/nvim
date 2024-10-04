---@class Command
---@field command string

---@class Maven_Runner
Runner = {}

local prefix = "maven-tools."

---@type Maven_Config
local maven_config = require(prefix .. "config.maven")

---@type Utils
local utils = require(prefix .. "utils")

---@type uv_process_t|nil
local runner_handle = nil

local current_command = ""
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_count = 10
local running = false
local success = false
local run_total_time = ""

local function real_time_notification()
    running = true
    local timer = vim.uv.new_timer()
    local counter = 1

    local function update_notification()
        if running then
            if counter > spinner_count then
                counter = 1
            end

            vim.api.nvim_echo({ { " " .. spinner[counter] .. " " .. current_command, "Normal" } }, false, {})
            counter = counter + 1
        else
            if run_total_time:len() > 0 then
                if success then
                    vim.api.nvim_echo(
                        { { "  " .. current_command .. ": done in " .. run_total_time, "DiagnosticOk" } },
                        false,
                        {}
                    )
                else
                    vim.api.nvim_echo(
                        { { "  " .. current_command .. ": failed in " .. run_total_time, "Error" } },
                        false,
                        {}
                    )
                end
            else
                vim.api.nvim_echo(
                    { { "  " .. current_command .. ": terminated", "WarningMsg" } },
                    false,
                    {}
                )
            end

            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
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

---@param entry Tree_Entry|Command
---@param pom_file string
---@param reset_callback fun()
---@param append_callback fun(lines:Array)
function Runner.run(entry, pom_file, reset_callback, append_callback)
    if entry.command == nil then
        return
    end

    if runner_handle ~= nil and not runner_handle:is_closing() then
        success = false
        run_total_time = ""
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

    reset_callback()

    local stdout = vim.uv.new_pipe(false)
    local stderr = vim.uv.new_pipe(false)

    local pipe_cmd = maven_config.runner_pipe_cmd(pom_file, { entry.command })
    current_command = entry.command

    real_time_notification()

    local cmd_str = pipe_cmd.cmd

    for _, arg in ipairs(pipe_cmd.args) do
        cmd_str = cmd_str .. " " .. arg
    end

    -- print(cmd_str)
    -- append_to_buffer({ cmd_str }, 1)

    append_callback(utils.Array():append(cmd_str))

    runner_handle = vim.uv.spawn(pipe_cmd.cmd, {
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
            local lines = utils.Array()
            -- local data_lines_count = 0
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

                        -- table.insert(lines, line)
                        lines:append(line)

                        -- data_lines_count = data_lines_count + 1
                    end
                end

                -- append_to_buffer(lines, data_lines_count)
                append_callback(lines)

                msg_buf = ""
            end
        end

        if err then
            success = false
        end
    end

    vim.uv.read_start(stdout, process_data)
    vim.uv.read_start(stderr, process_data)
end

return Runner
