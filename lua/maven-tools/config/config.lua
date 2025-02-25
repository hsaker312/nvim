---@class MavenToolsConfig
MavenToolsConfig = {}

MavenToolsConfig.version = "0.0.1"

---@type "Windows"|"Posix"
MavenToolsConfig.OS = package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" and "Windows" or "Posix"

MavenToolsConfig.cwd = vim.uv.cwd()

---@type boolean
MavenToolsConfig.recursivePomSearch = true

---@type boolean
MavenToolsConfig.multiproject = true

---@type boolean
MavenToolsConfig.refreshOnStartup = false

---@type string
MavenToolsConfig.localConfigDir = ".nvim/.maven"

---@type integer
MavenToolsConfig.maxParallelJobs = 4

---@type string[]
MavenToolsConfig.ignoreFiles = {
    "/META%-INF/",
    ".*/target/.*",
}

---@type string
MavenToolsConfig.tab = "   "

---@type string
MavenToolsConfig.defaultFilter = ""

---@type string[]
MavenToolsConfig.lifecycleCommands = {
    "clean",
    "install",
    "clean install",
}

MavenToolsConfig.showLifecycle = true
MavenToolsConfig.showPlugins = true
MavenToolsConfig.showDependencies = true
MavenToolsConfig.showRepositories = true
MavenToolsConfig.showFiles = true
MavenToolsConfig.autoRefreshProjectFiles = true
MavenToolsConfig.cacheEntries = true

return MavenToolsConfig
