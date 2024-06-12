local api = vim.api
local deployment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: " .. hl.symbols.pending .. "d " .. hl.symbols.clear .. "desc",
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
