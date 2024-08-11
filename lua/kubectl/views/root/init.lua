local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.root.definition")

local M = {}

function M.View()
  local self = ResourceBuilder:new("root"):display("k8s_root", "Root")

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
      :addHints({ { key = "<enter>", desc = "Select" } }, true, true, true)
      :setContent()
  end
end

return M
