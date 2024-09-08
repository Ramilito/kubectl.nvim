local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.root.definition")
local grid = require("kubectl.utils.grid")
local state = require("kubectl.state")
local timeme = require("kubectl.utils.timeme")

local M = {}

function M.View()
  timeme.start()
  ResourceBuilder:new(definition.resource)
    :display(definition.ft, definition.resource)
    :setCmd(definition.url, definition.cmd)
    :fetchAsync(function(builder)
      builder:decodeJson():process(definition.processRow):sort()
      vim.schedule(function()
        builder.prettyData, builder.extmarks =
          grid.pretty_print(definition.processRow(builder.data), definition.getSections())
        vim.print(builder.prettyData)
        builder:addHints(definition.hints, true, true, true):setContent(nil)
      end)

      timeme.stop()
    end)

  -- local self = ResourceBuilder:new(definition.resource):display(definition.ft, definition.display_name)
  --
  -- if self then
  --   self.data = {
  --     "Daemonsets",
  --     "Deployments",
  --     "└── Pods",
  --     "Events",
  --     "Nodes",
  --     "Secrets",
  --     "Services",
  --     "Cronjobs",
  --     "Jobs",
  --     "Configmaps",
  --     "PV",
  --     "PVC",
  --     "SA",
  --     "Clusterrolebinding",
  --     "CRDs",
  --   }
  --   self
  --     :process(definition.processRow, true)
  --     :sort()
  --     :prettyPrint(definition.getHeaders)
  --     :addHints(definition.hints, true, true, true)
  --     :setContent()
  -- end
end

return M
