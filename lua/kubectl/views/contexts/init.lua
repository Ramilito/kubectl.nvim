local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local definition = require("kubectl.views.contexts.definition")
local kube = require("kubectl.actions.kube")

local M = {
  contexts = {},
}

function M.View()
  local buf = buffers.floating_dynamic_buffer(definition.ft, definition.display_name, function(input)
    M.change_context(input)
  end, { header = { data = {} }, prompt = true })

  ResourceBuilder:new(definition.resource):setCmd(definition.url, "kubectl"):fetchAsync(function(self)
    self:decodeJson()

    vim.schedule(function()
      self.buf_nr = buf
      self:process(definition.processRow, true):prettyPrint(definition.getHeaders):setContent()

      local list = {}
      M.contexts = {}
      for _, value in ipairs(self.processedData) do
        if value.name.value then
          table.insert(M.contexts, value.name.value)
          table.insert(list, { name = value.name.value })
        end
      end
      completion.with_completion(buf, list)

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

--- Returns a list of context-names
--- @return string[]
function M.list_contexts()
  if #M.contexts > 0 then
    return M.contexts
  end
  local contexts = commands.shell_command("kubectl", { "config", "get-contexts", "-o", "name", "--no-headers" })
  M.contexts = vim.split(contexts, "\n")
  return M.contexts
end

--- Change context and restart proxy
--- @param cmd string
function M.change_context(cmd)
  local state = require("kubectl.state")
  local config = require("kubectl.config")
  if config.kubectl_cmd and config.kubectl_cmd.persist_context_change then
    local results = commands.shell_command("kubectl", { "config", "use-context", cmd })

    if not results then
      vim.notify(results, vim.log.levels.INFO)
    end
  end
  state.context["current-context"] = cmd
  kube.stop_kubectl_proxy()
  kube.start_kubectl_proxy(function()
    local cache = require("kubectl.cache")
    cache.LoadFallbackData(true)
    state.setup()
  end)
end

return M
