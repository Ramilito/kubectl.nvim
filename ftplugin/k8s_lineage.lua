local api = vim.api
local lineage_view = require("kubectl.views.lineage")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local kind, name, ns = lineage_view.getCurrentSelection()
      if name and ns then
        vim.api.nvim_set_option_value("modified", false, { buf = 0 })
        vim.cmd.close()

        view.view_or_fallback(kind)
      else
        api.nvim_err_writeln("Failed to select resource.")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
