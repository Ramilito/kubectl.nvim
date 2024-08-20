local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.namespace.definition")
local state = require("kubectl.state")

local M = {}

function M.View()
  local buf = buffers.namespace_buffer(definition.ft, function(input)
    M.changeNamespace(input)
  end, { title = definition.display_name, header = { data = {} } })

  ResourceBuilder:new(definition.resource):setCmd(definition.url, "curl"):fetchAsync(function(self)
    self:decodeJson()

    vim.schedule(function()
      self.buf_nr = buf
      self:process(definition.processRow):prettyPrint(definition.getHeaders):setContent()
      vim.api.nvim_buf_set_keymap(buf, "n", "<cr>", "", {
        noremap = true,
        callback = function()
          local current_word = vim.fn.expand("<cword>")

          vim.cmd("startinsert")
          vim.schedule(function()
            vim.api.nvim_put({ current_word }, "c", true, true)
          end)
        end,
      })
    end)
  end)
end

function M.changeNamespace(name)
  if name == "All" then
    state.ns = "All"
  else
    state.ns = name
    commands.shell_command("kubectl", { "config", "set-context", "--current", "--namespace=" .. name })
  end
end

return M
