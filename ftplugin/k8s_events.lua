local api = vim.api
local event_view = require("kubectl.views.events")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    callback = function()
      view.Hints({ { key = "<enter>", desc = "Read message" } })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    callback = function()
      local message = tables.getCurrentSelection(unpack({ 7 }))
      if message then
        event_view.ShowMessage(message)
      else
        print("Failed to extract event message.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
    noremap = true,
    silent = true,
    callback = function()
      event_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    callback = function()
      root_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(event_view.View)
  end
end

init()
