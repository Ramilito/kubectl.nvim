local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.namespace.definition")
local api = vim.api
local state = require("kubectl.state")

local M = {}

function M.View()
  ResourceBuilder:new(definition.resource)
    :displayFloatFit(definition.ft, definition.display_name)
    :setCmd(definition.url, "curl")
    :fetchAsync(function(self)
      self:decodeJson()
      vim.schedule(function()
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
            api.nvim_buf_delete(self.buf_nr, { force = true })
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
      api.nvim_buf_delete(0, { force = true })
      state.ns = name
      vim.schedule(function()
        local string_utils = require("kubectl.utils.string")
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(buf_name)))
        print("this should be true otherwise it's not understanding what view we are on", ok)
        if ok then
          pcall(view.View)
        else
          api.nvim_input("gr")
        end
      end)
    end)
  end
  if name == "All" then
    state.ns = "All"
    handle_output()
  else
    commands.shell_command("kubectl", { "config", "set-context", "--current", "--namespace=" .. name })
    handle_output()
  end
end

return M
