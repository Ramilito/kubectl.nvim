local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.events.definition")

local M = {}

function M.Events(cancellationToken)
  ResourceBuilder:new("events"):setCmd({ "get", "--raw", "/api/v1/{{NAMESPACE}}events" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

    vim.schedule(function()
      self
        :addHints({
          { key = "<enter>", desc = "message" },
        }, true, true)
        :display("k8s_events", "Events", cancellationToken)
    end)
  end)
end

function M.ShowMessage(event)
  local msg = event
  buffers.floating_buffer(vim.split(msg, "\n"), "event_msg", { title = "Message", syntax = "less" })
end

return M
