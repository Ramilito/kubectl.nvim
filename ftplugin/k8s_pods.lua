local api = vim.api
local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local container_view = require("kubectl.views.containers")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

local col_indices = { 1, 2 }
api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    local hints = ""
    hints = hints .. tables.generateHintLine("<l>", "Shows logs for all containers in pod \n")
    hints = hints .. tables.generateHintLine("<d>", "Describe selected pod \n")
    hints = hints .. tables.generateHintLine("<t>", "Show resources used \n")
    hints = hints .. tables.generateHintLine("<enter>", "Opens container view \n")
    hints = hints .. tables.generateHintLine("<shift-f>", "Port forward \n")
    hints = hints .. tables.generateHintLine("<C-k>", "Kill pod \n")
    view.Hints(hints)
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

api.nvim_buf_set_keymap(0, "n", "<C-k>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))

    if pod_name and namespace then
      print("Deleting pod..")
      commands.shell_command_async("kubectl", { "delete", "pod", pod_name, "-n", namespace })
      pod_view.Pods()
    else
      api.nvim_err_writeln("Failed to select pod.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<S-f>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      local current_port_query = "get pod " .. pod_name .. ' -o jsonpath="{.spec.containers[*].ports[*].containerPort}"'

      local current_port_result = commands.execute_shell_command("kubectl", current_port_query)

      vim.ui.input({ prompt = "source: " .. current_port_result .. ", destination: " }, function(input)
        if input ~= nil then
          actions.confirmation_buffer("Are you sure that you want to port forward to " .. input .. "?", nil, function(confirm)
            if confirm then
              local port_forward_query = { "port-forward", "pods/" .. pod_name, input .. ":" .. current_port_result }
              print(vim.inspect(port_forward_query))
              commands.shell_command_async("kubectl", port_forward_query, function(response)
                vim.schedule(function()
                  vim.notify(response)
                end)
              end)
            end
          end)
        end
      end)
    else
      api.nvim_err_writeln("Failed to select pod.")
    end
  end,
})

if not loop.is_running() then
  loop.start_loop(pod_view.Pods)
end
