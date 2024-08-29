local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local str = require("kubectl.utils.string")

mappings.map_if_plug_not_set("n", "f", "<Plug>(kubectl.follow)")
mappings.map_if_plug_not_set("n", "gw", "<Plug>(kubectl.wrap)")
mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.follow)", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      local container_view = require("kubectl.views.containers")
      pod_view.TailLogs(pod_view.selection.pod, pod_view.selection.ns, container_view.selection)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.wrap)", "", {
    noremap = true,
    silent = true,
    desc = "Toggle wrap",
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Add divider",
    callback = function()
      str.divider(bufnr)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
