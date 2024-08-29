local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local str = require("kubectl.utils.string")

mappings.map_if_plug_not_set("n", "f", "<Plug>(kubectl.follow)")
mappings.map_if_plug_not_set("n", "gw", "<Plug>(kubectl.wrap)")
mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.prefix)")
mappings.map_if_plug_not_set("n", "gt", "<Plug>(kubectl.timestamps)")
mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.follow)", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      pod_view.TailLogs()
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

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.timestamps)", "", {
    noremap = true,
    silent = true,
    desc = "Toggle timestamps",
    callback = function()
      if pod_view.show_timestamps == "true" then
        pod_view.show_timestamps = "false"
      else
        pod_view.show_timestamps = "true"
      end
      vim.cmd.close()
      pod_view.Logs()
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.prefix)", "", {
    noremap = true,
    silent = true,
    desc = "Toggle prefix",
    callback = function()
      if pod_view.show_log_prefix == "true" then
        pod_view.show_log_prefix = "false"
      else
        pod_view.show_log_prefix = "true"
      end
      vim.cmd.close()
      pod_view.Logs()
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
