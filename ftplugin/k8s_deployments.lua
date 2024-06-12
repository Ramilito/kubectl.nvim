local api = vim.api
local configmaps_view = require("kubectl.views.configmaps")
local deployment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local secrets_view = require("kubectl.views.secrets")
local services_view = require("kubectl.views.services")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: "
        .. hl.symbols.pending
        .. "d "
        .. hl.symbols.clear
        .. "desc | "
        .. hl.symbols.pending
        .. "<2> "
        .. hl.symbols.clear
        .. "pods | "
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

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  desc = "Desc",
  callback = function()
    local namespace, deployment_name = tables.getCurrentSelection(unpack({ 1, 2 }))
    if deployment_name and namespace then
      deployment_view.DeploymentDesc(deployment_name, namespace)
    else
      vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  desc = "kgp",
  callback = function()
    pod_view.Pods()
  end,
})

vim.api.nvim_buf_set_keymap(0, "n", "2", "", {
  noremap = true,
  silent = true,
  desc = "Pods",
  callback = function()
    pod_view.Pods()
  end,
})

vim.api.nvim_buf_set_keymap(0, "n", "3", "", {
  noremap = true,
  silent = true,
  desc = "Configmaps",
  callback = function()
    configmaps_view.Configmaps()
  end,
})

vim.api.nvim_buf_set_keymap(0, "n", "4", "", {
  noremap = true,
  silent = true,
  desc = "Secrets",
  callback = function()
    secrets_view.Secrets()
  end,
})

vim.api.nvim_buf_set_keymap(0, "n", "5", "", {
  noremap = true,
  silent = true,
  desc = "Services",
  callback = function()
    services_view.Services()
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  desc = "Back",
  callback = function()
    root_view.Root()
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    deployment_view.Deployments()
  end,
})

if not loop.is_running() then
  loop.start_loop(deployment_view.Deployments)
end
