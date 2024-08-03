local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.events.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("events")
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}events?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

      vim.schedule(function()
        self
          :addHints({
            { key = "<enter>", desc = "message" },
          }, true, true, true)
          :display("k8s_events", "Events", cancellationToken)
      end)
    end)
end

function M.ShowMessage(event)
  buffers.floating_buffer(vim.split(event, "\n"), {}, "event_msg", { title = "Message", syntax = "less" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(4, 1)
end

return M
