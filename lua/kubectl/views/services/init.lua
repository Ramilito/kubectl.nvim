local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("services")
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}services?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
      vim.schedule(function()
        self
          :addHints({
            { key = "<d>", desc = "describe" },
          }, true, true, true)
          :display("k8s_services", "Services", cancellationToken)
      end)
    end)
end

function M.Edit(name, namespace)
  buffers.floating_buffer({}, {}, "k8s_service_edit", { title = name, syntax = "yaml" })
  commands.execute_terminal("kubectl", { "edit", "services/" .. name, "-n", namespace })
end

function M.ServiceDesc(namespace, name)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_svc_desc", name, "yaml")
    :setCmd({ "describe", "svc", name, "-n", namespace })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:displayFloat("k8s_svc_desc", name, "yaml")
      end)
    end)
end

return M
