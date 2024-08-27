local container_view = require("kubectl.views.containers")
local pod_view = require("kubectl.views.pods")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local cl = config.options.keymaps.containers.logs
  vim.api.nvim_buf_set_keymap(bufnr, "n", cl.follow, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(cl.follow),
    callback = function()
      container_view.tailLogs(pod_view.selection.pod, pod_view.selection.ns)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", cl.wrap, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(cl.wrap),
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
