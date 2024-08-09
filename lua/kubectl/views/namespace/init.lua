local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.namespace.definition")
local api = vim.api
local state = require("kubectl.state")

local M = {}

function M.View()
  ResourceBuilder:new("namespace")
    :displayFloatFit("k8s_namespace", "Namespace")
    :setCmd({ "{{BASE}}/api/v1/namespaces?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson()
      if self.data.reason == "Forbidden" then
        self.data = { items = {} }

        for _, value in ipairs(config.options.namespace_fallback) do
          table.insert(self.data.items, {
            metadata = { name = value, creationTimestamp = nil },
            status = { phase = "nil" },
          })
        end
        self:process(definition.processLimitedRow, true)
      else
        self:process(definition.processRow, true)
      end
      self:sort():prettyPrint(definition.getHeaders)
      vim.schedule(function()
        if #self.prettyData == 1 then
          api.nvim_set_current_line("Access to namespaces denied, please input your desired namespace")
          api.nvim_set_option_value("buftype", "prompt", { buf = self.buf_nr })
          vim.fn.prompt_setcallback(self.buf_nr, function(input)
            api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
            M.changeNamespace(input)
          end)

          vim.cmd("startinsert")

          vim.keymap.set("n", "q", function()
            api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
            api.nvim_buf_delete(0, { force = true })
          end, { buffer = self.buf_nr, silent = true })
        else
          self:setContent()
          local line_count = api.nvim_buf_line_count(self.buf_nr)
          if line_count >= 2 then
            local win = api.nvim_get_current_win()
            api.nvim_win_set_cursor(win, { 2, 0 })
          end
        end
      end)
    end)
end
function M.changeNamespace(name)
  local function handle_output(_)
    vim.schedule(function()
      state.ns = name
      api.nvim_buf_delete(0, { force = true })
      api.nvim_input("gr")
    end)
  end
  if name == "All" then
    state.ns = "All"
    handle_output()
  else
    commands.shell_command_async(
      "kubectl",
      { "config", "set-context", "--current", "--namespace=" .. name },
      handle_output
    )
  end
end

return M
