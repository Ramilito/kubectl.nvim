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
    view.Hints({
      { key = "<l>", desc = "Shows logs for all containers in pod" },
      { key = "<d>", desc = "Describe selected pod" },
      { key = "<t>", desc = "Show resources used" },
      { key = "<enter>", desc = "Opens container view" },
      { key = "<shift-f>", desc = "Port forward" },
      { key = "<C-k>", desc = "Kill pod" },
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
      local current_port_query =
        { "get", "pod", pod_name, "-n", namespace, "-o", 'jsonpath="{.spec.containers[*].ports[*].containerPort}"' }

      local raw_output = commands.execute_shell_command("kubectl", current_port_query)
      local current_ports_result = vim.split(raw_output, " ")
      local current_port_result = current_ports_result[1]

      local confirmation_str = function(local_port, dest_port)
        return "Are you sure that you want to port forward from " .. dest_port .. " on " .. pod_name .. " to " .. local_port .. " locally?"
      end

      vim.ui.input({ prompt = "Local port: " }, function(local_port)
        if not local_port then
          return
        end
        if #current_ports_result > 1 then
          vim.ui.select(current_ports_result, { prompt = "Destination port: " }, function(dest_port)
            if not dest_port then
              return
            end
            current_port_result = dest_port
            actions.confirmation_buffer(confirmation_str(local_port, current_port_result), nil, function(confirm)
              if confirm then
                local port_forward_query = { "port-forward", "-n", namespace, "pods/" .. pod_name, local_port .. ":" .. dest_port }
                commands.shell_command_async("kubectl", port_forward_query, function(response)
                  vim.schedule(function()
                    vim.notify(response)
                  end)
                end)
              end
            end)
          end)
        else
          actions.confirmation_buffer(confirmation_str(local_port, current_port_result), nil, function(confirm)
            if confirm then
              local port_forward_query = { "port-forward", "-n", namespace, "pods/" .. pod_name, input .. ":" .. current_port_result }
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
