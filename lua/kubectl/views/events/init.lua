local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.events.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.ShowMessage(event)
  local buf = buffers.floating_buffer("event_msg", "Message", "less")
  buffers.set_content(buf, { content = vim.split(event, "\n"), {}, {} })
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "events_desc_" .. name .. "_" .. ns,
    ft = "k8s_desc",
    url = { "describe", "events", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(5, 1)
end

return M
