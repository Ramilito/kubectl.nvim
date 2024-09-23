local api = vim.api
local api_resources_view = require("kubectl.views.api-resources")
local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      overview_view.View()
    end,
  })
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local name = api_resources_view.getCurrentSelection()
      local view = require("kubectl.views")
      view.view_or_fallback(name)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(api_resources_view.View)
  end
end

init()
