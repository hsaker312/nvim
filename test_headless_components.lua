-- Load and configure our maven-tools-v2 plugin
local maven_tools = require("maven-tools-v2")

-- Setup with custom configurations to optimize for this complex workspace:
-- 1. recursivePomSearch = false (leverages our single-root reactor optimization)
-- 2. multiproject = true (so we resolve child modules)
maven_tools.setup({
    config = {
        recursivePomSearch = false,
        multiproject = true,
        autoStart = false,
    }
})

local importer = require("maven-tools-v2.maven.importer")

local finished = false

print("Starting scan of ~/msd/headless/components...")
importer.update("/home/helmy/msd/headless/components", function()
    print("Importer Status Change: " .. importer.status .. " (code: " .. tostring(importer.statusCode) .. ", progress: " .. string.format("%.1f", importer.progress()) .. "%)")
    
    if importer.statusCode == 5 then
        print("\n=== SUCCESS: Maven Tools Finished Scanning! ===")
        local projects_count = 0
        local error_projects_count = 0
        
        for _ in pairs(importer.mavenInfoToProjectInfoMap) do
            projects_count = projects_count + 1
        end
        for k, v in pairs(importer.pomFileToErrorMap) do
            error_projects_count = error_projects_count + 1
            print("  [Error Project] " .. k .. ": " .. tostring(v))
        end
        
        print("\nTotal Loaded Projects: " .. tostring(projects_count))
        print("Total Error Projects: " .. tostring(error_projects_count))
        print("Total Registered POM files: " .. tostring(importer.pomFiles:size()))
        
        -- Let's print out some sample projects to verify their structure is correct!
        print("\n=== Sample Projects Extracted ===")
        local samples = 0
        for infoStr, projectInfo in pairs(importer.mavenInfoToProjectInfoMap) do
            samples = samples + 1
            if samples <= 15 then
                print(string.format("Project %d: %s", samples, projectInfo.name))
                print("  Coordinates: " .. infoStr)
                print("  POM file: " .. tostring(projectInfo.pomFile))
                print("  Modules Count: " .. tostring(#projectInfo.modules))
                print("  Dependencies Count: " .. tostring(#projectInfo.dependencies))
                print("  Plugins Count: " .. tostring(#projectInfo.plugins))
            end
        end
        
        finished = true
    end
end)

-- Wait for the scan to finish, running the event loop under the hood. Timeout after 120 seconds.
print("Waiting for Maven scan to complete (may take a few seconds)...")
local ok, err = pcall(vim.wait, 120000, function()
    return finished
end, 200)

if not ok then
    print("\nError during wait: " .. tostring(err))
    os.exit(1)
elseif not finished then
    print("\nTimeout reached (120 seconds) before scanning completed.")
    os.exit(1)
else
    print("\nTest completed successfully!")
    os.exit(0)
end
