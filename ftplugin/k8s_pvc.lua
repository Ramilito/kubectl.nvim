local loop = require("kubectl.utils.loop")
local pvc_view = require("kubectl.views.pvc")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
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

      local resource = tables.find_resource(state.instance.data, name, ns)
      if not resource then
        return
      end
      local pv_name = resource.spec.volumeName

      -- add to filter and view
      require("kubectl.state").filter = pv_name
      pv_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(pvc_view.Draw)
  end
end

init()
