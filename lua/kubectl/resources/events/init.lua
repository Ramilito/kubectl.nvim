local buffers = require("kubectl.actions.buffers")
-- local definition = require("kubectl.resources.events.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "events"

---@class Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "Event" },
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "message", long_desc = "Read message" },
    },
    headers = {
      "NAMESPACE",
      "LAST SEEN",
      "TYPE",
      "REASON",
      "OBJECT",
      "COUNT",
      "MESSAGE",
    },
    -- processRow = definition.processRow,
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    builder.draw(cancellationToken)
  end
end

function M.ShowMessage(ns, object, event)
  local def = {
    resource = M.definition.resource .. "_msg",
    ft = "k8s_" .. M.definition.resource,
    display_name = "events | " .. object .. " | " .. ns,
    syntax = "less",
  }
  local builder = manager.get_or_create(def.resource)
  builder.buf_nr, builder.win_nr = buffers.floating_dynamic_buffer(def.ft, def.display_name, nil, { def.syntax })

  if builder then
    builder.addHints({ {
      key = "<Plug>(kubectl.quit)",
      desc = "quit",
    } }, false, false, false)
    builder.data = vim.split(event, "\n")

    builder.displayContentRaw()
    vim.api.nvim_set_option_value("wrap", true, { win = builder.win_nr })
  end
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }
  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      context = state.context["current-context"],
      gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = ns,
      name = name,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(5, 1)
end

return M
