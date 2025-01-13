return {
    "mfussenegger/nvim-jdtls",
    enabled = not vim.g.lite,
    dependencies = { "mfussenegger/nvim-dap" },
    ft = "java",
}
