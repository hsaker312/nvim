return {
  "eatgrass/maven.nvim",
  cmd = { "Maven", "MavenExec" },
  dependencies = "nvim-lua/plenary.nvim",
  config = function()
    require('maven').setup({
-- mvn -N wrapper:wrapper to generate mvnw
      executable="./mvnw"
    })
  end
}
