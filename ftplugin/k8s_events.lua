local api = vim.api
local event_view = require("kubectl.views.events")
local loop = require("kubectl.utils.loop")
local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
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
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(event_view.Draw)
  end
end

init()
