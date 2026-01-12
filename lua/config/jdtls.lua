local jdtls = require("jdtls")

local function get_jdtls()
    -- Get the Mason Registry to gain access to downloaded binaries
    local mason_registry = require("mason-registry")
    -- Find the full path to the directory where Mason has downloaded the JDTLS binaries
    local jdtls_path = vim.g.get_mason_package_path("jdtls")
    vim.notify(jdtls_path)
    -- Obtain the path to the jar which runs the language server
    local launcher = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")
    -- Obtain the path to configuration files for your specific operating system
    local jdtls_config = ""
    if vim.g.windows then
        jdtls_config = "/config_win"
    else
        jdtls_config = "/config_linux"
    end
    local config = jdtls_path .. jdtls_config
    -- Obtain the path to the Lomboc jar
    local lombok = jdtls_path .. "/lombok.jar"
    return launcher, config, lombok
end

local function get_bundles()
    -- Get the Mason Registry to gain access to downloaded binaries
    local mason_registry = require("mason-registry")
    -- Obtain the full path to the directory where Mason has downloaded the Java Debug Adapter binaries
    local java_debug_path = vim.g.get_mason_package_path("java-debug-adapter")

    local bundles = {
        vim.fn.glob(java_debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar", true),
    }

    -- Obtain the full path to the directory where Mason has downloaded the Java Test binaries
    local java_test_path = vim.g.get_mason_package_path("java-test")
    -- Add all of the Jars for running tests in debug mode to the bundles list
    vim.list_extend(bundles, vim.split(vim.fn.glob(java_test_path .. "/extension/server/*.jar", true), "\n"))

    return bundles
end

local home = vim.env.HOME

local function get_workspace()
    -- Get the home directory of your operating system
    -- Declare a directory where you would like to store project information
    local workspace_path = home .. "/.jdtls/workspace/"
    -- Determine the project name
    local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
    -- Create the workspace directory by concatenating the designated workspace path and the project name
    local workspace_dir = workspace_path .. project_name
    return workspace_dir
end

local function java_keymaps()
    -- Allow yourself to run JdtCompile as a Vim command
    vim.cmd(
        "command! -buffer -nargs=? -complete=custom,v:lua.require'jdtls'._complete_compile JdtCompile lua require('jdtls').compile(<f-args>)"
    )
    -- Allow yourself/register to run JdtUpdateConfig as a Vim command
    vim.cmd("command! -buffer JdtUpdateConfig lua require('jdtls').update_project_config()")
    -- Allow yourself/register to run JdtBytecode as a Vim command
    vim.cmd("command! -buffer JdtBytecode lua require('jdtls').javap()")
    -- Allow yourself/register to run JdtShell as a Vim command
    vim.cmd("command! -buffer JdtJshell lua require('jdtls').jshell()")

    -- Set a Vim motion to <Space> + <Shift>J + o to organize imports in normal mode
    vim.keymap.set(
        "n",
        "<leader>Jo",
        "<Cmd> lua require('jdtls').organize_imports()<CR>",
        { desc = "[J]ava [O]rganize Imports" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + v to extract the code under the cursor to a variable
    vim.keymap.set(
        "n",
        "<leader>Jv",
        "<Cmd> lua require('jdtls').extract_variable()<CR>",
        { desc = "[J]ava Extract [V]ariable" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + v to extract the code selected in visual mode to a variable
    vim.keymap.set(
        "v",
        "<leader>Jv",
        "<Esc><Cmd> lua require('jdtls').extract_variable(true)<CR>",
        { desc = "[J]ava Extract [V]ariable" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + <Shift>C to extract the code under the cursor to a static variable
    vim.keymap.set(
        "n",
        "<leader>JC",
        "<Cmd> lua require('jdtls').extract_constant()<CR>",
        { desc = "[J]ava Extract [C]onstant" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + <Shift>C to extract the code selected in visual mode to a static variable
    vim.keymap.set(
        "v",
        "<leader>JC",
        "<Esc><Cmd> lua require('jdtls').extract_constant(true)<CR>",
        { desc = "[J]ava Extract [C]onstant" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + t to run the test method currently under the cursor
    vim.keymap.set(
        "n",
        "<leader>Jt",
        "<Cmd> lua require('jdtls').test_nearest_method()<CR>",
        { desc = "[J]ava [T]est Method" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + t to run the test method that is currently selected in visual mode
    vim.keymap.set(
        "v",
        "<leader>Jt",
        "<Esc><Cmd> lua require('jdtls').test_nearest_method(true)<CR>",
        { desc = "[J]ava [T]est Method" }
    )
    -- Set a Vim motion to <Space> + <Shift>J + <Shift>T to run an entire test suite (class)
    vim.keymap.set("n", "<leader>JT", "<Cmd> lua require('jdtls').test_class()<CR>", { desc = "[J]ava [T]est Class" })
    -- Set a Vim motion to <Space> + <Shift>J + u to update the project configuration
    vim.keymap.set("n", "<leader>Ju", "<Cmd> JdtUpdateConfig<CR>", { desc = "[J]ava [U]pdate Config" })

    vim.keymap.set({ "n", "v" }, "<leader>cf", function()
        if vim.bo.filetype == "java" then
            vim.lsp.buf.format({ async = true })
        else
            require("lazyvim.util").format({ force = true })
        end
    end)

    vim.keymap.set(
        "n",
        "<leader>Jm",
        '<Esc><cmd>lua require("jdtls.dap").setup_dap_main_class_configs()<cr>',
        { desc = "[J]ava [U]pdate main methods" }
    )
end

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

local function get_class_paths(cwd, paths)
    local inti = false

    if paths == nil then
        paths = {}
        inti = true
    end

    if cwd == nil then
        cwd = vim.uv.cwd()
        if cwd == nil then
            return
        end
        cwd = cwd:gsub("%\\", "/")
    end

    local dirs = vim.fn.readdir(cwd)

    for _, dir in ipairs(dirs) do
        local path = cwd .. "/" .. dir
        local stat = vim.uv.fs_stat(path)
        -- print("0000000000")

        if stat ~= nil and stat.type == "directory" then
            -- print("1111111111")
            -- print(path)
            if path:match("/main/java/com$") ~= nil then
                -- print(path)
                local path_res = path:gsub("/com$", "")
                table.insert(paths, path_res)
            end

            get_class_paths(path, paths)
        end
    end

    if inti then
        return paths
    end
    --
    -- local res = ""
    --
    -- if inti then
    --     for _, path in ipairs(paths) do
    --         res = res .. path .. ";"
    --     end
    --
    --     if res ~= "" then
    --         res = res:sub(1, -2)
    --     end
    -- end
    --
    -- return res
end

local dapTargetIds = {}
local dapTargets = {}

local function get_root()
    dapTargetIds = {}
    dapTargets = {}

    local path = vim.uv.cwd() .. "/.nvim/jdtls.json"
    local res_file = io.open(path, "r")

    local root_dir = nil
    local maven = nil

    if res_file then
        local res_str = res_file:read("*a")
        res_file:close()
        local json = vim.fn.json_decode(res_str)

        if json.root ~= nil then
            root_dir = vim.uv.cwd() .. json.root
        end

        if json.maven ~= nil then
            maven = json.maven
            maven.userSettings = maven.userSettings
            maven.localRepository = maven.localRepository
        end

        if json.dap ~= nil then
            if json.dap.targets ~= nil then
                for k, v in pairs(json.dap.targets) do
                    local target = {
                        cmd = v.cmd,
                        args = {},
                    }

                    for _, arg in ipairs(v.args) do
                        local arg_str = arg:gsub("${cwd}", v.cwd)
                        table.insert(target.args, arg_str)
                    end

                    table.insert(dapTargetIds, v.id)
                    dapTargets[v.id] = target
                end
            end
        end
    end

    if root_dir == nil then
        root_dir = jdtls.setup.find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" })
    end

    if maven == nil then
        maven = {
            downloadSources = true,
        }
    end

    return root_dir, maven
end

vim.keymap.set("n", "<leader>Jud", get_root, { desc = "[J]ava [U]pdate [D]AP [T]argets" })

local launcher, os_config, lombok = get_jdtls()
local workspace_dir = get_workspace()
local bundles = get_bundles()
local root_dir, maven = get_root()
local runtimes = get_runtimes()
local dap = require("dap")

local function write_to_dap_console(message)
    vim.schedule(function()
        local session = dap.session()
        if session then
            -- This sends output to the DAP console
            -- vim.notify(message, vim.log.levels.INFO)
            -- For actual console output, we need to use the REPL
            local repl = require("dap.repl")
            if type(message) == "string" then
                local msg = message:gsub("[%c]", "")
                repl.append(msg .. "\n")
            end
        else
            print(message)
        end
    end)
end

local function get_dap_target()
    local co = coroutine.running()
    if not co then
        error("Must be called from a coroutine")
    end

    local targetId = nil
    local target = nil

    vim.ui.select(dapTargetIds, {
        prompt = "Select Target:",
    }, function(choice)
        targetId = choice
        target = dapTargets[targetId]

        if target then
            if target.cmd then
                coroutine.resume(co)
            else
                local runtimePaths = {}

                for _, v in pairs(runtimes) do
                    table.insert(runtimePaths, v.path)
                end

                vim.ui.select(runtimePaths, {
                    prompt = "Select Runtime:",
                }, function(selected_runtime)
                    if selected_runtime then
                        target.cmd = selected_runtime .. "/bin/java"
                        print(target.cmd)
                    else
                        target = nil
                    end
                    coroutine.resume(co)
                end)
            end
        else
            coroutine.resume(co)
        end
    end)

    coroutine.yield()
    return target
end

local dapHandle = nil

dap.listeners.after["event_terminated"]["kill_java_debug"] = function(session, body)
    if dapHandle ~= nil and not dapHandle:is_closing() then
        dapHandle:kill("sigterm")
    end
end

-- Handle disconnect
dap.listeners.after["disconnect"]["kill_java_debug"] = function(session, body)
    if dapHandle ~= nil and not dapHandle:is_closing() then
        dapHandle:kill("sigterm")
    end
end

-- Handle exit
dap.listeners.after["event_exited"]["kill_java_debug"] = function(session, body)
    if dapHandle ~= nil and not dapHandle:is_closing() then
        dapHandle:kill("sigterm")
    end
end

-- Handle unexpected termination
dap.listeners.after["error"]["kill_java_debug"] = function(session, body)
    if body and body.error then
        if dapHandle ~= nil and not dapHandle:is_closing() then
            dapHandle:kill("sigterm")
        end
    end
end

dap.configurations.java = {
    {
        type = "java",
        request = "attach",
        name = "Debug Custom Target",
        hostName = "127.0.0.1",
        port = function()
            local target = get_dap_target()

            if target == nil then
                print("Target not found")
                return
            end

            local pipe = { stdout = vim.uv.new_pipe(false), stderr = vim.uv.new_pipe(false) }
            dapHandle = vim.uv.spawn(target.cmd, {
                args = target.args,
                stdio = { nil, pipe.stdout, pipe.stderr },
            }, function()
                print("DAP Terminated!")

                pipe.stdout:close()
                pipe.stderr:close()
                if dapHandle ~= nil then
                    dapHandle:close()
                    dapHandle = nil
                end
            end)

            vim.uv.read_start(pipe.stdout, function(err, data)
                write_to_dap_console(err)
                write_to_dap_console(data)
            end)
            vim.uv.read_start(pipe.stderr, function(err, data)
                write_to_dap_console(err)
                write_to_dap_console(data)
            end)

            return "5005"
        end,
        console = "integratedTerminal",
        internalConsoleOptions = "openOnSessionStart",
        timeout = 30000,
    },
}

local function setup_jdtls()
    -- print(get_class_paths())
    -- Get access to the jdtls plugin and all of its functionality

    -- Get the paths to the jdtls jar, operating specific configuration directory, and lombok jar

    -- Get the path you specified to hold project information

    -- Get the bundles list with the jars to the debug adapter, and testing adapters

    -- Determine the root directory of the project by looking for these specific markers
    -- local root_dir = jdtls.setup.find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" })
    -- local root_dir = jdtls.setup.find_root({ ".jdtls" }) .. get_root()

    -- Tell our JDTLS language features it is capable of
    local capabilities = {
        workspace = {
            configuration = true,
        },
        textDocument = {
            completion = {
                snippetSupport = false,
            },
        },
    }

    local lsp_capabilities = require("blink-cmp").get_lsp_capabilities({}, true)

    for k, v in pairs(lsp_capabilities) do
        -- print(k, v)
        capabilities[k] = v
    end

    -- Get the default extended client capabilities of the JDTLS language server
    local extendedClientCapabilities = jdtls.extendedClientCapabilities
    -- Modify one property called resolveAdditionalTextEditsSupport and set it to true
    extendedClientCapabilities.resolveAdditionalTextEditsSupport = true

    -- Set the command that starts the JDTLS language server jar
    local cmd = {
        vim.g.windows and home .. "/.jdks/azul-21.0.6/bin/java.exe" or "java",
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Dlog.protocol=true",
        "-Dlog.level=ALL",
        -- "-Djava.class.path=" .. "C:/Users/saker.helmy/msd/headless/components/headless/MqttCommon/src/main/java",
        -- "-Dbranch=headless",
        "-Xmx16G",
        "--add-modules=ALL-SYSTEM",
        "--add-opens",
        "java.base/java.util=ALL-UNNAMED",
        "--add-opens",
        "java.base/java.lang=ALL-UNNAMED",
        "-javaagent:" .. lombok,
        "-jar",
        launcher,
        "-configuration",
        os_config,
        "-data",
        workspace_dir,
    }

    -- Configure settings in the JDTLS server
    local settings = {
        java = {
            project = {
                referencedLibraries = {
                    -- "C:/Users/saker.helmy/msd/headless/components/headless/MqttCommon/src/main/java"
                },
            },
            -- Enable code formatting
            format = {
                enabled = true,
                -- Use the Google Style guide for code formattingh
                settings = {
                    url = vim.fn.stdpath("config") .. "/java.style.xml",
                    profile = "GoogleStyle",
                },
            },
            -- Enable downloading archives from eclipse automatically
            eclipse = {
                downloadSource = true,
            },
            -- Enable downloading archives from maven automatically
            maven = maven,
            -- Enable method signature help
            signatureHelp = {
                enabled = true,
            },
            -- Use the fernflower decompiler when using the javap command to decompile byte code back to java code
            -- contentProvider = {
            --     preferred = "fernflower",
            -- },
            -- Setup automatical package import oranization on file save
            -- saveActions = {
            --     organizeImports = true,
            -- },
            -- Customize completion options
            completion = {
                -- When using an unimported static method, how should the LSP rank possible places to import the static method from
                favoriteStaticMembers = {
                    "org.hamcrest.MatcherAssert.assertThat",
                    "org.hamcrest.Matchers.*",
                    "org.hamcrest.CoreMatchers.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "java.util.Objects.requireNonNull",
                    "java.util.Objects.requireNonNullElse",
                    "org.mockito.Mockito.*",
                },
                -- Try not to suggest imports from these packages in the code action window
                filteredTypes = {
                    "com.sun.*",
                    "io.micrometer.shaded.*",
                    "java.awt.*",
                    "jdk.*",
                    "sun.*",
                },
                -- Set the order in which the language server should organize imports
                importOrder = {
                    "java",
                    "jakarta",
                    "javax",
                    "com",
                    "org",
                },
            },
            sources = {
                -- How many classes from a specific package should be imported before automatic imports combine them all into a single import
                organizeImports = {
                    starThreshold = 9999,
                    staticThreshold = 9999,
                },
                exclude = {
                    "**/node_modules/**",
                    "**/build/**",
                    "**/target/**",
                },
                include = {
                    "src/main/java/**",
                    "src/test/java/**",
                },
            },
            -- How should different pieces of code be generated?
            codeGeneration = {
                -- When generating toString use a json format
                toString = {
                    template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
                },
                -- When generating hashCode and equals methods use the java 7 objects method
                hashCodeEquals = {
                    useJava7Objects = true,
                },
                -- When generating code use code blocks
                useBlocks = true,
            },
            -- If changes to the project will require the developer to update the projects configuration advise the developer before accepting the change
            configuration = {
                updateBuildConfiguration = "interactive",
                runtimes = runtimes,
            },
            references = {
                includeDecompiledSources = true,
            },
            -- enable code lens in the lsp
            referencesCodeLens = {
                enabled = false,
            },
            -- enable inlay hints for parameter names,
            inlayHints = {
                parameterNames = {
                    enabled = "all",
                },
            },
        },
    }

    -- Create a table called init_options to pass the bundles with debug and testing jar, along with the extended client capablies to the start or attach function of JDTLS
    local init_options = {
        bundles = bundles,
        extendedClientCapabilities = extendedClientCapabilities,
    }

    -- Function that will be ran once the language server is attached
    local on_attach = function(_, bufnr)
        -- Map the Java specific key mappings once the server is attached
        java_keymaps()

        -- Setup the java debug adapter of the JDTLS server
        require("jdtls.dap").setup_dap()

        -- Find the main method(s) of the application so the debug adapter can successfully start up the application
        -- Sometimes this will randomly fail if language server takes to long to startup for the project, if a ClassDefNotFoundException occurs when running
        -- the debug tool, attempt to run the debug tool while in the main class of the application, or restart the neovim instance
        -- Unfortunately I have not found an elegant way to ensure this works 100%
        require("jdtls.dap").setup_dap_main_class_configs()
        -- Enable jdtls commands to be used in Neovim
        -- require("jdtls.setup").add_commands()
        -- Refresh the codelens
        -- Code lens enables features such as code reference counts, implementation counts, and more.
        -- vim.lsp.codelens.refresh()

        -- Setup a function that automatically runs every time a java file is saved to refresh the code lens
        -- vim.api.nvim_create_autocmd("BufWritePost", {
        --     pattern = { "*.java" },
        --     callback = function()
        --         local _, _ = pcall(vim.lsp.codelens.refresh)
        --     end,
        -- })
    end

    -- Create the configuration table for the start or attach function
    local config = {
        cmd = cmd,
        root_dir = root_dir,
        settings = settings,
        capabilities = capabilities,
        init_options = init_options,
        on_attach = on_attach,
    }

    vim.lsp.set_log_level("off")

    -- Start the JDTLS server
    require("jdtls").start_or_attach(config)
end

return {
    setup_jdtls = setup_jdtls,
}
