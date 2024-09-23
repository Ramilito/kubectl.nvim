local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local definition = require("kubectl.views.contexts.definition")
local kube = require("kubectl.actions.kube")

local M = {
  builder = nil,
  contexts = {},
}

function M.View()
  local buf = buffers.floating_dynamic_buffer(definition.ft, definition.display_name, function(input)
    M.change_context(input)
  end, { header = { data = {} }, prompt = true })
  if not M.builder then
    M.builder = ResourceBuilder:new(definition.resource):setCmd(definition.url, "kubectl"):fetch():decodeJson()
    M.builder:process(definition.processRow, true)
  end

  M.builder.buf_nr = buf
  M.builder:prettyPrint(definition.getHeaders):setContent()

  local list = {}
  M.contexts = {}
  for _, value in ipairs(M.builder.processedData) do
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
  local results = commands.shell_command("kubectl", { "config", "use-context", cmd })

  vim.notify(results, vim.log.levels.INFO)
  kube.stop_kubectl_proxy()
  kube.start_kubectl_proxy(function()
    local view = require("kubectl.views")
    local state = require("kubectl.state")
    view.LoadFallbackData(true)
    state.setup()
  end)
end

return M
