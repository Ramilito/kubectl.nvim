local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.namespace.definition")
local state = require("kubectl.state")

local M = {}

function M.View()
  local buf = buffers.floating_dynamic_buffer(definition.ft, definition.display_name, function(input)
    M.changeNamespace(input)
  end, { header = { data = {} }, prompt = true })

  ResourceBuilder:new(definition.resource):setCmd(definition.url, "curl"):fetchAsync(function(self)
    self:decodeJson()

    vim.schedule(function()
      self.buf_nr = buf
      self:process(definition.processRow):prettyPrint(definition.getHeaders):setContent()
      vim.api.nvim_buf_set_keymap(buf, "n", "<cr>", "", {
        noremap = true,
        callback = function()
          local line = vim.api.nvim_get_current_line()
          local current_word = vim.split(line, "%s%s+")[1]

          vim.cmd("startinsert")
          vim.schedule(function()
            vim.api.nvim_put({ current_word }, "c", true, true)
            vim.api.nvim_input("<cr>")
          end)
        end,
      })
    end)
  end)
end

function M.changeNamespace(name)
  state.ns = name
  if name ~= "All" then
    commands.shell_command("kubectl", { "config", "set-context", "--current", "--namespace=" .. name })
  end
end

return M
