local api = vim.api
local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    local hints = ""
    hints = hints .. tables.generateHintLine("<r>", "Restart selected deployment \n")
    hints = hints .. tables.generateHintLine("<d>", "Describe selected deployment \n")
    hints = hints .. tables.generateHintLine("<enter>", "Opens pods view \n")

    view.Hints(hints)
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

api.nvim_buf_set_keymap(0, "n", "r", "", {
  noremap = true,
  silent = true,
  callback = function()
    local ns, name = tables.getCurrentSelection(unpack({ 1, 2 }))
    actions.confirmation_buffer("Are you sure that you want to restart the deployment: " .. name, nil, function(confirm)
      if confirm then
        commands.shell_command_async(
          "kubectl",
          "rollout restart deployment/" .. name .. " -n " .. ns,
          function(response)
            vim.schedule(function()
              vim.notify(response)
            end)
          end
        )
      end
    end)
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
