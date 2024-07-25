local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  local pfs = {}
  definition.getPortForwards(pfs, true)
  ResourceBuilder:new("services")
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}services?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
      vim.schedule(function()
        definition.setPortForwards(self.extmarks, self.prettyData, pfs)
        self
          :addHints({
            { key = "<gd>", desc = "describe" },
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
