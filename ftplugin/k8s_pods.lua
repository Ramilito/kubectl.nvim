local api = vim.api
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")
local configmaps_view = require("kubectl.views.configmaps")
local container_view = require("kubectl.views.containers")
local deployments_view = require("kubectl.views.deployments")
local pod_view = require("kubectl.views.pods")
local secrets_view = require("kubectl.views.secrets")
local services_view = require("kubectl.views.services")

local col_indices = { 1, 2 }
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
        .. "<1> "
        .. hl.symbols.clear
        .. "deployments | "
        .. hl.symbols.pending
        .. "<3> "
        .. hl.symbols.clear
        .. "configmaps | "
        .. hl.symbols.pending
        .. "<4> "
        .. hl.symbols.clear
        .. "secrets",
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
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      pod_view.PodDesc(pod_name, namespace)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "l", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      pod_view.selectPod(pod_name, namespace)
      pod_view.PodLogs()
    else
      api.nvim_err_writeln("Failed to extract pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      pod_view.selectPod(pod_name, namespace)
      container_view.containers(pod_view.selection.pod, pod_view.selection.ns)
    else
      api.nvim_err_writeln("Failed to select pod.")
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

api.nvim_buf_set_keymap(0, "n", "1", "", {
  noremap = true,
  silent = true,
  desc = "Deployments",
  callback = function()
    deployments_view.Deployments()
  end,
})

api.nvim_buf_set_keymap(0, "n", "3", "", {
  noremap = true,
  silent = true,
  desc = "Configmaps",
  callback = function()
    configmaps_view.Configmaps()
  end,
})

api.nvim_buf_set_keymap(0, "n", "4", "", {
  noremap = true,
  silent = true,
  desc = "Secrets",
  callback = function()
    secrets_view.Secrets()
  end,
})

api.nvim_buf_set_keymap(0, "n", "5", "", {
  noremap = true,
  silent = true,
  desc = "Services",
  callback = function()
    services_view.Services()
  end,
})

if not loop.is_running() then
  loop.start_loop(pod_view.Pods)
end
