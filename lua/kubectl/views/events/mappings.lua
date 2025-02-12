local event_view = require("kubectl.views.events")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "View message",
    callback = function()
      local ns, object, message = tables.getCurrentSelection(unpack({ 1, 5, 7 }))
      if ns and object and message then
        event_view.ShowMessage(ns, object, message)
      else
        print("Failed to extract event message.")
      end
    end,
  },
}

return M
