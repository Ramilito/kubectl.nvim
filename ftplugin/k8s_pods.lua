-- k8s_pods.lua in ~/.config/nvim/ftplugin
local api = vim.api
local deployment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local pod_view = require("kubectl.views.pods")
local string_util = require("kubectl.utils.string")
local view = require("kubectl.views")

local function getCurrentSelection()
  local line = api.nvim_get_current_line()
  local columns = vim.split(line, hl.symbols.tab)
  local namespace = string_util.trim(columns[1])
  local pod_name = string_util.trim(columns[2])

  return namespace, pod_name
end

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

api.nvim_buf_set_keymap(0, "n", "t", "", {
  noremap = true,
  silent = true,
  callback = function()
    pod_view.PodTop()
  end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = getCurrentSelection()
    if pod_name and namespace then
      pod_view.PodDesc(pod_name, namespace)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  callback = function()
    deployment_view.Deployments()
  end,
})

api.nvim_buf_set_keymap(0, "n", "l", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = getCurrentSelection()
    if pod_name and namespace then
      pod_view.PodLogs(pod_name, namespace)
    else
      print("Failed to extract pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = getCurrentSelection()
    if pod_name and namespace then
      pod_view.PodContainers(pod_name, namespace)
    else
      print("Failed to extract containers.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    pod_view.Pods()
  end,
})
