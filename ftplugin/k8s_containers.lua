-- k8s_containers.lua in ~/.config/nvim/ftplugin
local api = vim.api
local hl = require("kubectl.actions.highlight")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: "
        .. hl.symbols.pending
        .. "l"
        .. hl.symbols.clear
        .. " logs | "
        .. hl.symbols.pending
        .. " d "
        .. hl.symbols.clear
        .. "desc | "
        .. hl.symbols.pending
        .. "<cr> "
        .. hl.symbols.clear
        .. "containers",
    })
  end,
})

api.nvim_buf_set_keymap(0, "n", "l", "", {
  noremap = true,
  silent = true,
  callback = function()
    local container_name = tables.getCurrentSelection(unpack({ 1 }))
    if container_name then
      pod_view.ContainerLogs(container_name)
    else
      print("Failed to extract logs.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local container_name = tables.getCurrentSelection(unpack({ 1 }))
    if container_name then
      pod_view.ExecContainer(container_name)
    else
      print("Failed to extract containers.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    pod_view.PodContainers()
  end,
})
