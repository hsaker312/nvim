vim.g.lite = true
vim.g.windows = package.cpath:match("%p[\\|/]?%p(%a+)") == "dll"

require("config.lazy")
