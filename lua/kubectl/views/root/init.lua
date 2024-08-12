local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.root.definition")

local M = {}

function M.View()
  local self = ResourceBuilder:new(definition.resource):display(definition.ft, definition.display_name)

  if self then
    self.data = {
      "Daemonsets",
      "Deployments",
      "└── Pods",
      "Events",
      "Nodes",
      "Secrets",
      "Services",
      "Configmaps",
    }
    self
      :process(definition.processRow, true)
      :sort()
      :prettyPrint(definition.getHeaders)
      :addHints(definition.hints, true, true, true)
      :setContent()
  end
end

return M
