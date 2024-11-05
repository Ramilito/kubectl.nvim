local api = vim.api
local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local container_view = require("kubectl.views.containers")
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.logs)", "", {
    noremap = true,
    silent = true,
    desc = "View logs",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if name and ns then
        pod_view.selectPod(name, ns)
        pod_view.Logs()
      else
        api.nvim_err_writeln("Failed to extract pod name or namespace.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if name and ns then
        pod_view.selectPod(name, ns)
        container_view.View(pod_view.selection.pod, pod_view.selection.ns)
      else
        api.nvim_err_writeln("Failed to select pod.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.kill)", "", {
    noremap = true,
    silent = true,
    desc = "delete pod",
    callback = function()
      local selections = state.getSelections()
      if vim.tbl_count(selections) == 0 then
        local name, ns = pod_view.getCurrentSelection()
        if name and ns then
          selections = { { name = name, namespace = ns } }
        else
          api.nvim_err_writeln("Failed to select pod.")
        end
      end

      local prompt = "Are you sure you want to delete the selected pod(s)?"
      buffers.confirmation_buffer(prompt, "prompt", function(confirm)
        if confirm then
          for _, selection in ipairs(selections) do
            local name = selection.name
            local ns = selection.namespace

            local port_forwards = {}
            root_definition.getPFData(port_forwards, false, "pods")
            for _, pf in ipairs(port_forwards) do
              if pf.resource == name then
                vim.notify("Killing port forward for " .. pf.resource)
                commands.shell_command_async("kill", { pf.pid })
              end
            end
            vim.notify("Deleting pod " .. name)
            commands.shell_command_async("kubectl", { "delete", "pod", name, "-n", ns })
          end
          state.selections = {}
          pod_view.Draw()
        end
      end)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.portforward)", "", {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()

      if not ns or not name then
        api.nvim_err_writeln("Failed to select pod for port forward")
        return
      end

      pod_view.PortForward(name, ns)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(pod_view.Draw)
  end
end

init()

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gl", "<Plug>(kubectl.logs)")
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.portforward)")
  mappings.map_if_plug_not_set("n", "gk", "<Plug>(kubectl.kill)")
end)
