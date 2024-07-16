local jdtls_config = ""

if package.cpath:match("%p[\\|/]?%p(%a+)") == "dll" then
    jdtls_config = "/config_win"
else
    jdtls_config = "/config_linux"
end

local home = vim.env.HOME
local jdk = vim.fn.getenv("NVIM_JDTLS_JDK")
local java = vim.fn.getenv("NVIM_JDTLS_JAVA")

if jdk == nil or jdk == "" or jdk == vim.NIL then
    jdk = vim.fn.getenv("JAVA_HOME")

    if jdk == nil or jdk == "" or jdk == vim.NIL then
        jdk = "/usr/lib/jvm/default/"
    end
end

if java == nil or java == "" or java == vim.NIL then
    java = "java"
end

local jdtls = require("jdtls")
local jdtls_path = require("mason-registry").get_package("jdtls"):get_install_path()
local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
local workspace_dir = home .. "/jdtls-workspace/" .. project_name

local bundles = {
    vim.fn.glob(
        home .. "/build/java-debug/com.microsoft.java.debug.plugin/target/com.microsoft.java.debug.plugin-*.jar"
    ),
}

local function get_runtimes()
    local dirs = { "/usr/lib/jvm/", home .. "/.jdks/" }
    local res = {}

    for _, dir in ipairs(dirs) do
        if vim.loop.fs_stat(dir) then
            local files = vim.fn.readdir(dir)

            for _, file in ipairs(files) do
                if file ~= "." and file ~= ".." then
                    local stat = vim.loop.fs_stat(dir .. file)

                    if stat then
                        if stat.type == "directory" then
                            local version = file:match("%d+")

                            if version then
                                if version == "1" then
                                    version = "1.8"
                                end

                                table.insert(res, {
                                    name = "JavaSE-" .. version,
                                    path = dir .. file,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return res
end

local runtimes = get_runtimes()

local config = {
    cmd = {
        java,
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Dlog.protocol=true",
        "-Dlog.level=ALL",
        "-Djava.class.path=" .. home .. "/maven/repos/headless",
        "-Dbranch=headless",
        "-Xmx1g",
        "--add-modules=ALL-SYSTEM",
        "--add-opens",
        "java.base/java.util=ALL-UNNAMED",
        "--add-opens",
        "java.base/java.lang=ALL-UNNAMED",
        "-javaagent:" .. jdtls_path .. "/lombok.jar",
        "-jar",
        vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar"),
        "-configuration",
        jdtls_path .. jdtls_config,
        "-data",
        workspace_dir,
    },

    -- root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" }),
    root_dir = require("jdtls.setup").find_root({ ".jdtls" }),

    settings = {
        java = {
            -- TODO Replace this with the absolute path to your main java version (JDK 17 or higher)
            home = home .. "/.jdks/azul-1.8.0_412",
            eclipse = {
                downloadSources = true,
            },
            configuration = {
                updateBuildConfiguration = "interactive",
                -- TODO Update this by adding any runtimes that you need to support your Java projects and removing any that you don't have installed
                -- The runtime name parameters need to match specific Java execution environments.  See https://github.com/tamago324/nlsp-settings.nvim/blob/2a52e793d4f293c0e1d61ee5794e3ff62bfbbb5d/schemas/_generated/jdtls.json#L317-L334
                runtimes = runtimes,
            },
            maven = {
                downloadSources = true,
                userSettings = home .. "/.m2/settings.xml",
                localRepository = home .. "/maven/repos/headless",
            },
            implementationsCodeLens = {
                enabled = true,
            },
            referencesCodeLens = {
                enabled = true,
            },
            references = {
                includeDecompiledSources = true,
            },
            inlayHints = {
                parameterNames = {
                    enabled = "all", -- literals, all, none
                },
            },
            signatureHelp = { enabled = true },
            import = {
                maven = {
                    enabled = true,
                    offline = false
                }
            },
            format = {
                enabled = true,
                -- Formatting works by default, but you can refer to a specific file/URL if you choose
                -- settings = {
                --   url = "https://github.com/google/styleguide/blob/gh-pages/intellij-java-google-style.xml",
                --   profile = "GoogleStyle",
                -- },
            },
        },
        completion = {
            favoriteStaticMembers = {
                "org.hamcrest.MatcherAssert.assertThat",
                "org.hamcrest.Matchers.*",
                "org.hamcrest.CoreMatchers.*",
                "org.junit.jupiter.api.Assertions.*",
                "java.util.Objects.requireNonNull",
                "java.util.Objects.requireNonNullElse",
                "org.mockito.Mockito.*",
            },
            importOrder = {
                "java",
                "javax",
                "com",
                "org",
            },
        },
        extendedClientCapabilities = jdtls.extendedClientCapabilities,
        sources = {
            organizeImports = {
                starThreshold = 9999,
                staticStarThreshold = 9999,
            },
        },
        codeGeneration = {
            toString = {
                template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
            },
            useBlocks = true,
        },
    },

    capabilities = require("cmp_nvim_lsp").default_capabilities(),
    flags = {
        allow_incremental_sync = true,
    },
    init_options = {
        -- References the bundles defined above to support Debugging and Unit Testing
        bundles = bundles,
    },
}

-- Needed for debugging
config["on_attach"] = function(client, bufnr)
    jdtls.setup_dap({ hotcodereplace = "auto" })
    require("jdtls.dap").setup_dap_main_class_configs()
end

vim.keymap.set({ "n", "v" }, "<leader>cf", function()
    vim.lsp.buf.format({ async = true })
end)
-- This starts a new client & server, or attaches to an existing client & server based on the `root_dir`.
jdtls.start_or_attach(config)

-- require("lspconfig").jdtls.setup({})
