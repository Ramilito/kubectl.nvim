local pvc_view = require("kubectl.views.pvc")
local pvc_definiton = require("kubectl.views.pvc.definition")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to PVs",
    callback = function()
      local pv_view = require("kubectl.views.pv")
      local name, ns = pvc_view.getCurrentSelection()
      if not name or not ns then
        return pv_view.View()
      end

      -- get pv of pvc
      local state = require("kubectl.state")
      local resource = tables.find_resource(state.instance[pvc_definiton.resource].data, name, ns)
      if not resource then
        return
      end
      local pv_name = resource.spec.volumeName

      -- add to filter and view
      state.setFilter(pv_name)
      pv_view.View()
    end,
  },
}

return M
