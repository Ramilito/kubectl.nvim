local actions = require("kubectl.actions")
local commands = require("kubectl.commands")
local events = require("kubectl.events")
local find = require("kubectl.utils.find")
local tables = require("kubectl.view.tables")

local M = {}

function M.Events()
  local results = commands.execute_shell_command("kubectl", { "get", "events", "-A", "-o=json" })
  local data = events.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, events.getHeaders())
  local hints = tables.generateHints({
    { key = "<enter>", desc = "message" },
  }, true, true)

  actions.buffer(find.filter_line(pretty, FILTER), "k8s_events", { hints = hints, title = "Events" })
end

function M.ShowMessage(event)
  local msg = event
  actions.floating_buffer(vim.split(msg, "\n"), "event_msg", { title = "Message", syntax = "less" })
end

return M
