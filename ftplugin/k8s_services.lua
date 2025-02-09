local api = vim.api
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local service_view = require("kubectl.views.services")
local state = require("kubectl.state")
local view = require("kubectl.views")
local err_msg = "Failed to extract service name or namespace."

--- Set key mappings for the buffer
local function set_keymap(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = service_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.portforward)", "", {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = function()
      local name, ns = service_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end

      service_view.PortForward(name, ns)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymap(0)
  if not loop.is_running() then
    loop.start_loop(service_view.Draw)
  end
end

init()

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.portforward)")
end)
