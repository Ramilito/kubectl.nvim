local api = vim.api
local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local root_view = require("kubectl.views.root")
local service_view = require("kubectl.views.services")
local tables = require("kubectl.utils.tables")

mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.portforward)")

--- Set key mappings for the buffer
local function set_keymap(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.portforward)", "", {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = function()
      local name, ns = service_view.getCurrentSelection()

      if not ns or not name then
        api.nvim_err_writeln("Failed to select service for port forward")
        return
      end

      ResourceBuilder:new("services_pf")
        :setCmd({
          "{{BASE}}/api/v1/namespaces/" .. ns .. "/services/" .. name .. "?pretty=false",
        }, "curl")
        :fetchAsync(function(self)
          self:decodeJson()
          local data = {}

          for _, port in ipairs(self.data.spec.ports) do
            table.insert(data, {
              name = { value = port.name, symbol = hl.symbols.pending },
              port = { value = port.port, symbol = hl.symbols.success },
              protocol = port.protocol,
            })
          end

          vim.schedule(function()
            local win_config
            self.buf_nr, win_config = buffers.confirmation_buffer(
              "Confirm port forward",
              "PortForward",
              function(confirm)
                if confirm then
                  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                  local container_port, local_port

                  for _, line in ipairs(lines) do
                    if line:match("Container port:") then
                      container_port = line:match("::(%d+)$")
                    elseif line:match("Local port:") then
                      local_port = line:match("Local port: (.*)")
                    end
                  end
                  commands.shell_command_async(
                    "kubectl",
                    { "port-forward", "-n", ns, "svc/" .. name, local_port .. ":" .. container_port }
                  )

                  vim.schedule(function()
                    service_view.View()
                  end)
                end
              end
            )

            self.prettyData, self.extmarks = tables.pretty_print(data, { "NAME", "PORT", "PROTOCOL" })

            table.insert(self.prettyData, "")
            table.insert(
              self.prettyData,
              "Container port: " .. (data[1].name.value or "<unset>") .. "::" .. data[1].port.value
            )
            table.insert(self.prettyData, "Local port: " .. data[1].port.value)
            table.insert(self.prettyData, "")
            local confirmation = "[y]es [n]o:"
            local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
            table.insert(self.prettyData, padding .. confirmation)

            self:setContent()
          end)
        end)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymap(0)
  if not loop.is_running() then
    loop.start_loop(service_view.Draw)
  end
end

init()
