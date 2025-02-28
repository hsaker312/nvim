---@class Command
---@field command string

---@class MavenRunner
MavenToolsRunner = {}

local prefix = "maven-tools."

---@type MavenToolsConfig
local mavenConfig = require(prefix .. "config.maven")

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type uv.uv_process_t|nil
local runnerHandle = nil

local currentCommand = ""
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinnerCount = 10
local running = false
local success = false
local runTotalTime = ""

local function real_time_notification()
    running = true
    local timer = vim.uv.new_timer()
    local counter = 1

    local function update_notification()
        if running then
            if counter > spinnerCount then
                counter = 1
            end

            -- vim.notify(" " .. spinner[counter] .. " " .. current_command, vim.log.levels.TRACE)
            vim.api.nvim_echo({ { " " .. spinner[counter] .. " " .. currentCommand, "Normal" } }, false, {})
            counter = counter + 1
        else
            if runTotalTime:len() > 0 then
                if success then
                    -- vim.notify(current_command .. ": done in " .. run_total_time, vim.log.levels.OFF)
                    vim.api.nvim_echo(
                        { { "  " .. currentCommand .. ": done in " .. runTotalTime, "DiagnosticOk" } },
                        false,
                        {}
                    )
                else
                    vim.notify(currentCommand .. ": failed in " .. runTotalTime, vim.log.levels.ERROR)
                end
            else
                vim.notify(currentCommand .. ": terminated", vim.log.levels.WARN)
                -- vim.api.nvim_echo({ { "  " .. current_command .. ": terminated", "WarningMsg" } }, false, {})
            end

            if timer ~= nil then
                timer:stop()
                if not timer:is_closing() then
                    timer:close()
                end
            end
        end
    end

    if timer ~= nil then
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
end

local msgBuf = ""

---@param entry TreeEntry|Command
---@param pom_file string
---@param reset_callback fun()
---@param append_callback fun(lines:Array)
function MavenToolsRunner.run(entry, pom_file, reset_callback, append_callback)
    if entry.command == nil then
        return
    end

    if runnerHandle ~= nil and not runnerHandle:is_closing() then
        success = false
        runTotalTime = ""
        runnerHandle:kill("sigterm")
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

    if stdout == nil or stderr == nil then
        return
    end

    local pipeCmd = mavenConfig.runner_pipe_cmd(pom_file, { entry.command })
    print(vim.inspect(pipeCmd))
    currentCommand = entry.command

    real_time_notification()

    local cmd_str = pipeCmd.cmd

    for _, arg in ipairs(pipeCmd.args) do
        cmd_str = cmd_str .. " " .. arg
    end

    -- print(cmd_str)
    -- append_to_buffer({ cmd_str }, 1)

    append_callback(utils.Array():append(cmd_str))

    runnerHandle = vim.uv.spawn(pipeCmd.cmd, {
        args = pipeCmd.args,
        stdio = { nil, stdout, stderr },
    }, function()
        running = false
        stdout:close()
        stderr:close()

        if runnerHandle ~= nil then
            runnerHandle:close()
            runnerHandle = nil
        end
    end)

    local function process_data(err, data)
        if data then
            local lines = utils.Array()
            -- local data_lines_count = 0
            data = data:gsub("[\r\n|\n\r]", "\n"):gsub("\r", ""):gsub("\27%[m", "\27%[0m")
            msgBuf = msgBuf .. data

            local msgLen = #msgBuf
            if msgBuf:sub(msgLen, msgLen) == "\n" then
                for line in data:gmatch("[^\n]+") do
                    ---@cast line string
                    if line ~= "" then
                        if line:match("BUILD FAILURE") or line:match("ERROR") then
                            success = false
                        elseif line:match("BUILD SUCCESS") then
                            success = true
                        elseif line:match("Total time:") then
                            runTotalTime = line:gsub(".+Total time:", ""):gsub("%s", "")
                        end

                        -- table.insert(lines, line)
                        lines:append(line)

                        -- data_lines_count = data_lines_count + 1
                    end
                end

                -- append_to_buffer(lines, data_lines_count)
                append_callback(lines)

                msgBuf = ""
            end
        end

        if err then
            success = false
        end
    end

    vim.uv.read_start(stdout, process_data)
    vim.uv.read_start(stderr, process_data)
end

return MavenToolsRunner
