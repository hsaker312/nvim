local maven_tools = require("maven-tools-v2")
local utils = require("maven-tools-v2.utils")

maven_tools.setup({
    config = {
        recursivePomSearch = false,
        multiproject = true,
        autoStart = false,
    },
    maven = {
        importerOptions = {
            "maven.repo.local=/home/helmy/drives/ssd0/maven.repos/headless",
            "branch=headless",
            "msd.native.skip=true",
            "org.ops4j.pax.url.mvn.localRepository=/home/helmy/drives/ssd0/maven.repos/headless",
            "org.ops4j.pax.url.mvn.repositories=http://swproductsrepo.meso-scale.com/nexus/content/groups/headless@id=nexus",
            "org.ops4j.pax.url.mvn.defaultRepositories=/home/helmy/drives/ssd0/maven.repos/headless",
            "maven.test.skip=true",
            "skipITs=true",
            "license.skip.collect=true",
            "jarsigner.skip=true",
            "msd.clean-database.skip",
        }
    }
})

local importer = require("maven-tools-v2.maven.importer")

-- Hook into start_pom_file_processor_task callback by overwriting the task manager run or extract function!
local original_extract = importer.extract_effective_pom
importer.extract_effective_pom = function(xmlStr)
    print("LIVE DIAGNOSTIC: xmlStr length is " .. tostring(#xmlStr))
    local ext = original_extract(xmlStr)
    print("LIVE DIAGNOSTIC: extracted XML length is " .. tostring(ext and #ext or "nil"))
    return ext
end

local original_update = importer.update
local finished = false

importer.update("/home/helmy/msd/headless/components", function()
    print("LIVE DIAGNOSTIC: callback triggered. statusCode: " .. tostring(importer.statusCode))
    
    if importer.statusCode == 3 then
        local count = 0
        for k, v in pairs(importer.mavenInfoToProjectInfoMap) do
            count = count + 1
        end
        print("LIVE DIAGNOSTIC: projects in map: " .. tostring(count))
        
        local err_count = 0
        for k, v in pairs(importer.pomFileToErrorMap) do
            err_count = err_count + 1
            print("LIVE DIAGNOSTIC: error project: " .. k .. " -> " .. tostring(v):sub(1, 100))
        end
        
        finished = true
    end
end)

pcall(vim.wait, 60000, function() return finished end, 200)
os.exit(0)
