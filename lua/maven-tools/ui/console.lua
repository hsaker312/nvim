---@class MavenConsoleWindow
MavenToolsConsole = {}

local prefix = "maven-tools."

---@type MavenUtils
local utils = require(prefix .. "utils")

---@type Baleia
local baleia = require(prefix .. "deps.baleia.lua.baleia").setup({ log = "ERROR" })

---@type integer|nil
local consoleWin = nil

---@type integer|nil
local consoleBuf = nil

---@type integer[]
local autocmds = {}

---@type integer
local linesCount = 0

local function create_buf()
    if consoleBuf ~= nil then
        return
    end

    consoleBuf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_option_value("modifiable", true, {
        buf = consoleBuf,
    })

    vim.api.nvim_set_option_value("buftype", "nofile", {
        buf = consoleBuf,
    })

    vim.api.nvim_set_option_value("swapfile", false, {
        buf = consoleBuf,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "q", "<cmd>quit<CR>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "i", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "I", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "a", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "A", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "o", "<nop>", {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(consoleBuf, "n", "O", "<nop>", {
        noremap = true,
        silent = true,
    })
end

local function window_close_handler()
    consoleWin = nil
    consoleBuf = nil

    for _, autocmd in ipairs(autocmds) do
        vim.api.nvim_del_autocmd(autocmd)
    end

    autocmds = {}
end

local function create_win()
    if consoleWin ~= nil then
        return
    end

    create_buf()

    if consoleBuf ~= nil then
        local currentWin = vim.api.nvim_get_current_win()
        -- local cursor = vim.api.nvim_win_get_cursor(current_win)

        consoleWin = vim.api.nvim_open_win(consoleBuf, true, {
            split = "below",
            win = -1,
            height = 10,
        })

        vim.api.nvim_set_current_win(currentWin)
        -- vim.api.nvim_win_set_cursor(current_win, )

        vim.api.nvim_set_option_value("number", false, {
            win = consoleWin,
        })

        vim.api.nvim_set_option_value("spell", false, {
            win = consoleWin,
        })

        table.insert(
            autocmds,
            vim.api.nvim_create_autocmd("WinClosed", {
                callback = function(event)
                    if consoleWin ~= nil then
                        if tonumber(event.match) == consoleWin then
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
                    if consoleWin ~= nil and consoleBuf ~= nil then
                        local new_buf = vim.api.nvim_win_get_buf(consoleWin)

                        if new_buf ~= consoleBuf then
                            vim.schedule(function()
                                vim.api.nvim_win_set_buf(consoleWin, consoleBuf)

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
    if consoleBuf == nil then
        return
    end

    -- Get the total number of lines in the buffer
    local totalLines = vim.api.nvim_buf_line_count(consoleBuf)

    -- Get the current window's cursor position (line, column)
    ---@diagnostic disable-next-line: param-type-mismatch
    local currentCursorPosition = vim.api.nvim_win_get_cursor(consoleWin)

    -- Get the number of visible lines in the current window
    ---@diagnostic disable-next-line: param-type-mismatch
    local visibleLines = vim.api.nvim_win_get_height(consoleWin)

    -- Calculate the last visible line in the window
    local lastVisibleLine = currentCursorPosition[1] + visibleLines - 1

    -- Check if the last visible line is greater than or equal to the total number of lines
    return lastVisibleLine >= totalLines
end

local function clear_buffer()
    if consoleBuf then
        vim.api.nvim_set_option_value("modifiable", true, {
            buf = consoleBuf,
        })

        baleia.buf_set_lines(consoleBuf, 0, -1, true, {})
        -- vim.api.nvim_buf_set_lines(runner_buf_id, 0, -1, true, {})
        linesCount = 0

        vim.api.nvim_set_option_value("modifiable", false, {
            buf = consoleBuf,
        })
    end
end

---@param lines Array
function MavenToolsConsole.console_append(lines)
    if consoleBuf == nil then
        return
    end

    vim.schedule(function()
        local scroll = should_console_scroll()

        vim.api.nvim_set_option_value("modifiable", true, {
            buf = consoleBuf,
        })

        local lastline = vim.api.nvim_buf_line_count(consoleBuf)

        baleia.buf_set_lines(consoleBuf, lastline, lastline, true, lines:values())
        -- vim.api.nvim_buf_set_lines(runner_buf_id, lastline, lastline, true, lines)

        vim.api.nvim_set_option_value("modifiable", false, {
            buf = consoleBuf,
        })

        linesCount = linesCount + lines:size()

        if scroll then
            vim.api.nvim_buf_call(consoleBuf, function()
                vim.cmd("normal! G")
            end)
        end
    end)
end

function MavenToolsConsole.console_reset()
    clear_buffer()
    create_win()
end

function MavenToolsConsole.show()
    create_win()
end

function MavenToolsConsole.hide()
    if consoleWin == nil then
        return
    end

    vim.api.nvim_win_close(consoleWin, false)
end

function MavenToolsConsole.toggle()
    if consoleWin ~= nil then
        vim.api.nvim_win_close(consoleWin, false)
    else
        create_win()
    end
end

return MavenToolsConsole
