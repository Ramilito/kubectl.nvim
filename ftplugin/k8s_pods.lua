local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local container_view = require("kubectl.views.containers")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local pod_definition = require("kubectl.views.pods.definition")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local col_indices = { 1, 2 }
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints({
        { key = "<gd>", desc = "Describe selected pod" },
        { key = "<gk>", desc = "Kill pod" },
        { key = "<gl>", desc = "Shows logs for all containers in pod" },
        { key = "<gp>", desc = "Port forward" },
        { key = "<gP>", desc = "View active Port forwards" },
        { key = "<gu>", desc = "Show resources used" },
        { key = "<enter>", desc = "Opens container view" },
      })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gu", "", {
    noremap = true,
    silent = true,
    desc = "Resources used",
    callback = function()
      pod_view.PodTop()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gd", "", {
    noremap = true,
    silent = true,
    desc = "Describe resource",
    callback = function()
      local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
      if pod_name and namespace then
        pod_view.PodDesc(pod_name, namespace)
      else
        api.nvim_err_writeln("Failed to describe pod name or namespace.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      deployment_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gl", "", {
    noremap = true,
    silent = true,
    desc = "View logs",
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

  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
      if pod_name and namespace then
        pod_view.selectPod(pod_name, namespace)
        container_view.View(pod_view.selection.pod, pod_view.selection.ns)
      else
        api.nvim_err_writeln("Failed to select pod.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gk", "", {
    noremap = true,
    silent = true,
    desc = "Kill pod",
    callback = function()
      local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))

      if pod_name and namespace then
        local port_forwards = {}
        pod_definition.getPortForwards(port_forwards, false)
        for _, pf in ipairs(port_forwards) do
          if pf.resource == pod_name then
            vim.notify("Killing port forward for " .. pf.resource)
            commands.shell_command_async("kill", { pf.pid })
          end
        end
        vim.notify("Deleting pod " .. pod_name)
        commands.shell_command_async("kubectl", { "delete", "pod", pod_name, "-n", namespace })
        pod_view.View()
      else
        api.nvim_err_writeln("Failed to select pod.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gP", "", {
    noremap = true,
    silent = true,
    desc = "View Port Forwards",
    callback = function()
      pod_view.PodPF()
    end,
  })
  api.nvim_buf_set_keymap(bufnr, "n", "gp", "", {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = function()
      local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
      if pod_name and namespace then
        local current_port_query =
          { "get", "pod", pod_name, "-n", namespace, "-o", 'jsonpath="{.spec.containers[*].ports[*].containerPort}"' }

        local raw_output = commands.execute_shell_command("kubectl", current_port_query)
        local current_ports_result = vim.split(raw_output, " ")
        local current_port_result = current_ports_result[1]

        local confirmation_str = function(local_port, dest_port)
          return "Are you sure that you want to port forward from "
            .. dest_port
            .. " on "
            .. pod_name
            .. " to "
            .. local_port
            .. " locally?"
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
              buffers.confirmation_buffer(confirmation_str(local_port, current_port_result), "prompt", function(confirm)
                if confirm then
                  local port_forward_query =
                    { "port-forward", "-n", namespace, "pods/" .. pod_name, local_port .. ":" .. dest_port }
                  commands.shell_command_async("kubectl", port_forward_query, function(response)
                    vim.schedule(function()
                      vim.notify(response)
                    end)
                  end)
                end
              end)
            end)
          else
            buffers.confirmation_buffer(confirmation_str(local_port, current_port_result), "prompt", function(confirm)
              if confirm then
                local port_forward_query =
                  { "port-forward", "-n", namespace, "pods/" .. pod_name, local_port .. ":" .. current_port_result }
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
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(pod_view.View)
  end
end

init()
