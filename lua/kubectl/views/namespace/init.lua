local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.namespace.definition")
local state = require("kubectl.state")

local M = {}

function M.View()
  ResourceBuilder:new("namespace")
    :displayFloatFit("k8s_namespace", "Namespace")
    :setCmd({ "{{BASE}}/api/v1/namespaces?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow, true):sort():prettyPrint(definition.getHeaders)
      vim.schedule(function()
        self:setContent()

        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(win, { 2, 0 })
      end)
    end)
end
function M.changeNamespace(name)
  local function handle_output(_)
    vim.schedule(function()
      state.ns = name
      vim.api.nvim_buf_delete(0, { force = false })
      vim.api.nvim_input("gr")
    end)
  end
  if name == "All" then
    state.ns = "All"

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_input("gr")
  else
    commands.shell_command_async(
      "kubectl",
      { "config", "set-context", "--current", "--namespace=" .. name },
      handle_output
    )
  end
end

return M
