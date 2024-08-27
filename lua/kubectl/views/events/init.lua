local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.events.definition")
local tables = require("kubectl.utils.tables")

local M = { builder = nil }

function M.View(cancellationToken)
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Draw(cancellationToken)
  M.builder = M.builder:draw(definition, cancellationToken)
end

function M.ShowMessage(event)
  local buf = buffers.floating_buffer("event_msg", "Message", "less")
  buffers.set_content(buf, { content = vim.split(event, "\n"), {}, {} })
end

function M.Desc(name, ns)
  ResourceBuilder:view_float({
    resource = "desc",
    ft = "k8s_event_desc",
    url = { "describe", "events", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(5, 1)
end

return M
