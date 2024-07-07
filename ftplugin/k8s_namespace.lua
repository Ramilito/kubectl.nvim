local api = vim.api
local namespace_view = require("kubectl.views.namespace")
local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    callback = function()
      local name = tables.getCurrentSelection(unpack({ 1 }))
      if name then
        namespace_view.changeNamespace(name)
      else
        print("Failed to get namespace.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
    noremap = true,
    silent = true,
    callback = function()
      namespace_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
