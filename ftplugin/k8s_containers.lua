local api = vim.api
local container_view = require("kubectl.views.containers")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "gl", "", {
    noremap = true,
    silent = true,
    desc = "View logs",
    callback = function()
      local container_name = tables.getCurrentSelection(unpack({ 1 }))
      if container_name then
        container_view.selectContainer(container_name)
        container_view.logs(pod_view.selection.pod, pod_view.selection.ns)
      else
        print("Failed to extract logs.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Exec into",
    callback = function()
      local container_name = tables.getCurrentSelection(unpack({ 1 }))
      if container_name then
        container_view.selectContainer(container_name)
        container_view.exec(pod_view.selection.pod, pod_view.selection.ns)
      else
        print("Failed to extract containers.")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
