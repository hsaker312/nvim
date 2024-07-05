-- M = {}
--
-- M.maven_win = -1
-- M.items = {}
-- M.line_callbacks = {}
--
-- return M
--
local function create_256_color_highlight_groups()
    -- Define 256 colors mapping using xterm colors
    local xterm_colors = {
        -- 0-7: standard colors
        [0] = "#000000",
        [1] = "#800000",
        [2] = "#008000",
        [3] = "#808000",
        [4] = "#000080",
        [5] = "#800080",
        [6] = "#008080",
        [7] = "#c0c0c0",
        -- 8-15: high intensity colors
        [8] = "#808080",
        [9] = "#ff0000",
        [10] = "#00ff00",
        [11] = "#ffff00",
        [12] = "#0000ff",
        [13] = "#ff00ff",
        [14] = "#00ffff",
        [15] = "#ffffff",
        -- 16-231: 6x6x6 color cube
        [16] = "#000000",
        [17] = "#00005f",
        [18] = "#000087",
        [19] = "#0000af",
        -- The rest of the 256 color palette goes here...
        [230] = "#ffd7af",
        [231] = "#ffffff",
        -- 232-255: grayscale
        [232] = "#080808",
        [233] = "#121212",
        [234] = "#1c1c1c",
        [235] = "#262626",
        [236] = "#303030",
        [237] = "#3a3a3a",
        [238] = "#444444",
        [239] = "#4e4e4e",
        [240] = "#585858",
        [241] = "#626262",
        [242] = "#6c6c6c",
        [243] = "#767676",
        [244] = "#808080",
        [245] = "#8a8a8a",
        [246] = "#949494",
        [247] = "#9e9e9e",
        [248] = "#a8a8a8",
        [249] = "#b2b2b2",
        [250] = "#bcbcbc",
        [251] = "#c6c6c6",
        [252] = "#d0d0d0",
        [253] = "#dadada",
        [254] = "#e4e4e4",
        [255] = "#eeeeee",
    }

    for i = 0, 255 do
        local color = xterm_colors[i]
        if color then
            vim.cmd(string.format("highlight AnsiColor%d guifg=%s", i, color))
        end
    end
end

local function apply_ansi_highlights(bufnr, lines)
    create_256_color_highlight_groups()

    local ns_id = vim.api.nvim_create_namespace("ansi_highlights")
    local pos = 0

    for i, line in ipairs(lines) do
        local start_pos = pos
        pos = pos + #line + 1 -- +1 for newline character
        local col_start = 0
        local hl_group = nil
        local col_end = 0
        local plain_text = ""

        while true do
            local ansi_start, ansi_end, code = line:find("\27%[([0-9;]+)m", col_end + 1)
            print(ansi_start, ansi_end, code)
            if not ansi_start then
                plain_text = plain_text .. line:sub(col_end + 1)
                break
            end
            plain_text = plain_text .. line:sub(col_end + 1, ansi_start - 1)
            col_start = #plain_text

            local codes = {}
            for c in code:gmatch("%d+") do
                table.insert(codes, tonumber(c))
            end

            -- Assuming color code is the last code and handles 38;5;color_code
            local color_code = nil
            if #codes >= 3 and codes[1] == 38 and codes[2] == 5 then
                color_code = codes[3]
            end
            hl_group = color_code and ("AnsiColor" .. color_code) or nil

            col_end = ansi_end

            if hl_group then
                print(hl_group)
                vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, i, 0, 10)
            end
        end

        -- Apply highlight if we have an hl_group

        -- Insert the plain text without escape codes
        vim.api.nvim_buf_set_lines(bufnr, start_pos, start_pos + 1, false, { plain_text })
    end
end

-- Example usage
local bufnr = vim.api.nvim_create_buf(false, true)

vim.api.nvim_open_win(bufnr, true, {
    split = "below",
    win = -1,
    height = 10,
})

local lines = {
    "Normal text",
    "\27[38;5;196mRed text\27[0m Normal text",
    "\27[38;5;46mGreen text\27[0m Normal text",
}

apply_ansi_highlights(bufnr, lines)
