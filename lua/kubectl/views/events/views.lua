local actions = require("kubectl.actions.actions")
local events = require("kubectl.views.events")
local ResourceBuilder = require("kubectl.resourcebuilder")

local M = {}

function M.Events()
  ResourceBuilder:new("events", { "get", "events", "-A", "-o=json" })
    :fetch()
    :decodeJson()
    :process(events.processRow)
    :prettyPrint(events.getHeaders)
    :addHints({
      { key = "<enter>", desc = "message" },
    }, true, true)
    :setFilter(FILTER)
    :display("k8s_events", "Events")
end

function M.ShowMessage(event)
  local msg = event
  actions.floating_buffer(vim.split(msg, "\n"), "event_msg", { title = "Message", syntax = "less" })
end

return M
