local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.events.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("events")
    :display("k8s_events", "Events", cancellationToken)
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}events?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

      vim.schedule(function()
        self
          :addHints({
            { key = "<gd>", desc = "describe" },
            { key = "<enter>", desc = "message" },
          }, true, true, true)
          :setContent(cancellationToken)
      end)
    end)
end

function M.ShowMessage(event)
  local buf = buffers.floating_buffer("event_msg", "Message", "less")
  buffers.set_content(buf, { content = vim.split(event, "\n"), {}, {} })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_event_desc", name, "yaml")
    :setCmd({ "describe", "events", name, "-n", ns })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:setContentRaw()
      end)
    end)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(5, 1)
end

return M
