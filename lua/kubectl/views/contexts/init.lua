local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")

local resource = "contexts"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    url = { "config", "view", "-ojson" },
    headers = {
      "NAME",
      "NAMESPACE",
      "CLUSTER",
      "USER",
    },
  },
  contexts = {},
}

function M.View()
  local buf, win = buffers.floating_dynamic_buffer(M.definition.ft, M.definition.display_name, function(input)
    M.change_context(input)
  end, { header = { data = {} }, prompt = true })

  local self = manager.get_or_create(M.definition.resource)
  self.definition = M.definition

  commands.run_async("get_config_async", {}, function(data)
    self.data = data
    self.decodeJson()

    vim.schedule(function()
      self.buf_nr = buf
      self.process(M.processRow, true).prettyPrint().displayContent(win)

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

  local client = require("kubectl.client")
  local self = manager.get_or_create(M.definition.resource)
  self.data = client.get_config()
  self.decodeJson()

  M.contexts = {}
  for _, context in ipairs(self.data.contexts) do
    if context.name then
      table.insert(M.contexts, context.name)
    end
  end

  return M.contexts
end

--- Change context and restart proxy
--- @param cmd string
function M.change_context(cmd)
  local state = require("kubectl.state")

  -- TODO: keep persist functionality?
  -- local config = require("kubectl.config")
  -- if config.kubectl_cmd and config.kubectl_cmd.persist_context_change then
  --   local results = commands.shell_command("kubectl", { "config", "use-context", cmd })
  --
  --   if not results then
  --     vim.notify(results, vim.log.levels.INFO)
  --   end
  -- end
  state.context["current-context"] = cmd

  local client = require("kubectl.client")
  client.set_implementation()
  state.setup()
  local cache = require("kubectl.cache")
  cache.LoadFallbackData(true)
end

function M.processRow(rows)
  local data = {}
  -- rows.contexts
  for _, row in ipairs(rows.contexts) do
    local context = {
      name = { value = row.name, symbol = hl.symbols.success },
      namespace = row.context.namespace or "",
      cluster = row.context.cluster or "",
      user = row.context.user or "",
    }

    table.insert(data, context)
  end

  return data
end

return M
