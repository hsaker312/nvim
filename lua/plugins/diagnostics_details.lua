return {
    "hsaker312/diagnostics-details.nvim",
    config = function ()
        require("diagnostics-details").setup({
            max_window_height_fallback = 10,
            auto_close_on_focus_lost = true
        })
    end
}
