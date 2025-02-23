---@class MavenToolsConfig
MavenToolsConfig = {}

MavenToolsConfig.version = "0.0.1"

---@type "Windows"|"Posix"
MavenToolsConfig.OS = package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" and "Windows" or "Posix"

MavenToolsConfig.cwd = vim.uv.cwd()

---@type boolean
MavenToolsConfig.recursive_pom_search = true

---@type boolean
MavenToolsConfig.multiproject = true

---@type boolean
MavenToolsConfig.refresh_on_startup = true

---@type boolean
MavenToolsConfig.auto_refresh = true

---@type string
MavenToolsConfig.local_config_dir = ".nvim/.maven"

---@type integer
MavenToolsConfig.max_parallel_jobs = 4

---@type string[]
MavenToolsConfig.ignore_files = { "/META%-INF/" }

---@type string
MavenToolsConfig.tab = "   "

---@type string
MavenToolsConfig.default_filter = ""

---@type string[]
MavenToolsConfig.lifecycle_commands = {
    "clean",
    "install",
    "clean install",
}

MavenToolsConfig.show_lifecycle = true
MavenToolsConfig.show_plugins = true
MavenToolsConfig.show_dependencies = true
MavenToolsConfig.show_repositories = true
MavenToolsConfig.show_files = true
MavenToolsConfig.auto_update_project_files = true
MavenToolsConfig.cacheEntries = false

return MavenToolsConfig
