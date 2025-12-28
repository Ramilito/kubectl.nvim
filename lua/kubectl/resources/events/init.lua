local BaseResource = require("kubectl.resources.base_resource")
local buffers = require("kubectl.actions.buffers")
local manager = require("kubectl.resource_manager")

local resource = "events"

local M = BaseResource.extend({
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
    "NAME",
  },
}, {
  name_column_index = 8,
  namespace_column_index = 1,
})

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

return M
