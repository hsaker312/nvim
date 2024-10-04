---@class Maven_Console_Window
Maven_Console_Window = {}

local prefix = "maven-tools."

---@type Utils
local utils = require(prefix .. "utils")

local baleia = require("maven-tools.deps.baleia.lua.baleia").setup({ log = "ERROR" })

---@type integer|nil
local runner_win_id = nil

---@type integer|nil
local runner_buf_id = nil

---@type integer[]
local autocmds = {}

---@type integer
local lines_count = 0

local function create_buf()
    if runner_buf_id ~= nil then
        return
    end

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

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "q", "<cmd>quit<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "i", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "I", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "a", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "A", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "o", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(runner_buf_id, "n", "O", "<nop>", {
        noremap = true,
        silent = true,
    })
end

local function window_close_handler()
    print("closing console")
    runner_win_id = nil

    for _, autocmd in ipairs(autocmds) do
        vim.api.nvim_del_autocmd(autocmd)
    end

    autocmds = {}
end

local function create_win()
    if runner_win_id ~= nil then
        return
    end

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
                            window_close_handler()
                        end
                    end
                end,
            })
        )

        table.insert(
            autocmds,
            vim.api.nvim_create_autocmd("BufWinEnter", {
                callback = function()
                    if runner_win_id ~= nil and runner_buf_id ~= nil then
                        local new_buf = vim.api.nvim_win_get_buf(runner_win_id)

                        if new_buf ~= runner_buf_id then
                            vim.schedule(function()
                                vim.api.nvim_win_set_buf(runner_win_id, runner_buf_id)

                                local editor_win = utils.get_editor_window()

                                if editor_win ~= nil then
                                    vim.api.nvim_win_set_buf(editor_win, new_buf)
                                end
                            end)
                        end
                    end
                end,
            })
        )
    end
end

---@return boolean|nil
local function should_console_scroll()
    if runner_buf_id == nil then
        return
    end

    -- Get the total number of lines in the buffer
    local total_lines = vim.api.nvim_buf_line_count(runner_buf_id)

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

local function clear_buffer()
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

---@param lines Array
function Maven_Console_Window.console_append(lines)
    if runner_buf_id == nil then
        return
    end

    vim.schedule(function()
        local scroll = should_console_scroll()

        vim.api.nvim_set_option_value("modifiable", true, {
            buf = runner_buf_id,
        })

        local lastline = vim.api.nvim_buf_line_count(runner_buf_id)

        baleia.buf_set_lines(runner_buf_id, lastline, lastline, true, lines:values())
        -- vim.api.nvim_buf_set_lines(runner_buf_id, lastline, lastline, true, lines)

        vim.api.nvim_set_option_value("modifiable", false, {
            buf = runner_buf_id,
        })

        lines_count = lines_count + lines:size()

        if scroll then
            vim.api.nvim_buf_call(runner_buf_id, function()
                vim.cmd("normal! G")
            end)
        end
    end)
end

function Maven_Console_Window.console_reset()
    clear_buffer()
    create_win()
end

function Maven_Console_Window.show()
    create_win()
end

function Maven_Console_Window.hide()
    if runner_win_id == nil then
        return
    end

    vim.api.nvim_win_close(runner_win_id, false)
end

function Maven_Console_Window.toggle()
    if runner_win_id ~= nil then
        vim.api.nvim_win_close(runner_win_id, false)
    else
        create_win()
    end
end

return Maven_Console_Window
