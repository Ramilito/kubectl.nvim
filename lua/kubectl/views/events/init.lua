local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")
local definition = require("kubectl.views.events.definition")

local M = {}

function M.Events(cancellationToken)
  ResourceBuilder:new("events", { "get", "events", "-A", "-o=json" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders):setFilter()

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
  actions.floating_buffer(vim.split(msg, "\n"), "event_msg", { title = "Message", syntax = "less" })
end

return M
