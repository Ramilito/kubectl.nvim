local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.configmaps.definition")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("configmaps"):setCmd({ "get", "--raw", "/api/v1/{{NAMESPACE}}configmaps" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true)
        :display("k8s_configmaps", "Configmaps", cancellationToken)
    end)
  end)
end

function M.Edit(name, namespace)
  buffers.floating_buffer({}, {}, "yaml", {})
  local cmd = "kubectl edit configmaps/" .. name .. " -n " .. namespace
  vim.fn.termopen(cmd)
end

function M.ConfigmapsDesc(namespace, name)
  ResourceBuilder:new("desc")
    :setCmd({ "describe", "configmaps", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_configmaps_desc", name, "yaml")
end

return M
