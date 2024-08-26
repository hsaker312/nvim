return {
    "mfussenegger/nvim-jdtls",
    enabled = not vim.g.vscode,
    dependencies = { "mfussenegger/nvim-dap" },
    ft = "java",
}
