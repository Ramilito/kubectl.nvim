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

      local resource = tables.find_resource(state.instance.data, name, ns)
      if not resource then
        return
      end

      local self = ResourceBuilder:new("pods_pf")
      local data = {}
      for _, container in ipairs(resource.spec.containers) do
        if container.ports then
          for _, port in ipairs(container.ports) do
            table.insert(data, {
              name = { value = port.name, symbol = hl.symbols.pending },
              port = { value = port.containerPort, symbol = hl.symbols.success },
              protocol = port.protocol,
            })
          end
        end
      end

      vim.schedule(function()
        if next(data) == nil then
          api.nvim_err_writeln("No container ports exposed in pod")
          return
        end

        local win_config
        self.buf_nr, win_config = buffers.confirmation_buffer("Confirm port forward", "PortForward", function(confirm)
          if not confirm then
            return
          end
          local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
          local container_port, local_port

          local port_pattern = ".+:%s*(%d+)"
          for _, line in ipairs(lines) do
            if line:match("Container port:") then
              container_port = line:match(port_pattern)
            elseif line:match("Local port:") then
              local_port = line:match(port_pattern)
            end
          end
          if not container_port or not local_port then
            api.nvim_err_writeln("Failed to extract container port or local port")
            return
          end
          commands.shell_command_async(
            "kubectl",
            { "port-forward", "-n", ns, "pods/" .. name, local_port .. ":" .. container_port }
          )

          vim.schedule(function()
            pod_view.View()
          end)
        end)

        self.prettyData, self.extmarks = tables.pretty_print(data, { "NAME", "PORT", "PROTOCOL" })

        table.insert(self.prettyData, "")
        table.insert(self.prettyData, "Container port: " .. data[1].port.value)
        table.insert(self.prettyData, "Local port:     " .. data[1].port.value)
        table.insert(self.prettyData, "")

        local confirmation = "[y]es [n]o | `gr` to reset"
        local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
        table.insert(self.prettyData, padding .. confirmation)

        local original_data = vim.deepcopy(self.prettyData)

        self:setContent()
        api.nvim_buf_set_keymap(self.buf_nr, "n", "gr", "", {
          noremap = true,
          silent = true,
          desc = "Reset",
          callback = function()
            self.prettyData = original_data
            self:setContent()
          end,
        })
        api.nvim_buf_set_keymap(self.buf_nr, "n", "<CR>", "", {
          noremap = true,
          silent = true,
          desc = "Change container port",
          callback = function()
            local port_ok, port = pcall(tables.getCurrentSelection, 2)
            if not port_ok or not port or not tonumber(port) then
              return
            end
            local line = "Container port: " .. port
            api.nvim_buf_set_lines(self.buf_nr, #self.prettyData - 4, #self.prettyData - 3, false, { line })
          end,
        })
      end)
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
