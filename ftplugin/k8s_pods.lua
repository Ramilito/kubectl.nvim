local api = vim.api
local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local container_view = require("kubectl.views.containers")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local err_msg = "Failed to extract pod name or namespace."

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.logs)", "", {
    noremap = true,
    silent = true,
    desc = "View logs",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      pod_view.selectPod(name, ns)
      pod_view.Logs()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      pod_view.selectPod(name, ns)
      container_view.View(pod_view.selection.pod, pod_view.selection.ns)
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
          vim.notify(err_msg, vim.log.levels.ERROR)
        end
      end

      local self = ResourceBuilder:new("kill_pods")
      local data = {}
      for _, value in ipairs(selections) do
        table.insert(data, { name = value.name, namespace = value.namespace })
      end
      self.data = data
      self.processedData = self.data

      local prompt = "Are you sure you want to delete the selected resource(s)?"
      local buf_nr, win_config = buffers.confirmation_buffer(prompt, "prompt", function(confirm)
        if confirm then
          for _, selection in ipairs(selections) do
            local name = selection.name
            local ns = selection.namespace

            local port_forwards = {}
            root_definition.getPFData(port_forwards, false)
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
          vim.schedule(function()
            pod_view.Draw()
          end)
        end
      end)

      self.buf_nr = buf_nr
      self.prettyData, self.extmarks = tables.pretty_print(self.processedData, { "NAME", "NAMESPACE" })

      table.insert(self.prettyData, "")
      table.insert(self.prettyData, "")
      local confirmation = "[y]es [n]o"
      local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
      table.insert(self.extmarks, {
        row = #self.prettyData - 1,
        start_col = 0,
        virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
        virt_text_pos = "inline",
      })
      self:setContent()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.portforward)", "", {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if not ns or not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
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
