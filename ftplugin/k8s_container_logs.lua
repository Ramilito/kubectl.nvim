local container_view = require("kubectl.views.containers")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local str = require("kubectl.utils.string")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.previous_logs)", "", {
    noremap = true,
    silent = true,
    desc = "Previous logs",
    callback = function()
      if container_view.show_previous == "true" then
        container_view.show_previous = "false"
      else
        container_view.show_previous = "true"
      end
      container_view.logs(pod_view.selection.pod, pod_view.selection.ns, false)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.follow)", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
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

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.history)", "", {
    noremap = true,
    silent = true,
    desc = "Log history",
    callback = function()
      vim.ui.input({ prompt = "Since (seconds)=", default = container_view.log_since }, function(input)
        container_view.log_since = input
        container_view.logs(pod_view.selection.pod, pod_view.selection.ns, false)
      end)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "f", "<Plug>(kubectl.follow)")
  mappings.map_if_plug_not_set("n", "gw", "<Plug>(kubectl.wrap)")
  mappings.map_if_plug_not_set("n", "gh", "<Plug>(kubectl.history)")
  mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
  mappings.map_if_plug_not_set("n", "p", "<Plug>(kubectl.previous_logs)")
end)
