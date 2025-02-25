local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.events.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance[definition.resource]:draw(definition, cancellationToken)
end

function M.ShowMessage(ns, object, event)
  local builder = ResourceBuilder:new("events")
  builder:displayFloatFit("k8s_event_msg", "events | " .. object .. " | " .. ns, "less")
  builder:addHints({ {
    key = "<Plug>(kubectl.quit)",
    desc = "quit",
  } }, false, false, false)
  builder.data = vim.split(event, "\n")
  builder:setContentRaw()
  vim.api.nvim_set_option_value("wrap", true, { win = builder.win_nr })
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "events | " .. name .. " | " .. ns,
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
