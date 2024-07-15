---@class Config
Config = {}

Config.version = "0.0.1"

---@type boolean
Config.recursive_pom_search = true

---@type boolean
Config.multiproject = true

---@type boolean
Config.refresh_on_startup = true

---@type boolean
Config.auto_refresh = true

---@type string
Config.local_config_dir = ".nvim/.maven"

---@type integer
Config.max_parallel_jobs = 4

---@type string[]
Config.ignore_files = {"/META%-INF/"}

return Config

