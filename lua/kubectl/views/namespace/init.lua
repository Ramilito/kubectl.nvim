local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local definition = require("kubectl.views.namespace.definition")
local state = require("kubectl.state")

local resource = "namespaces"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "namespace" },
    headers = {
      "NAME",
      "STATUS",
      "AGE",
    },
  },
  namespaces = { "All" },
}

function M.View()
  local buf = buffers.floating_dynamic_buffer(M.definition.ft, M.definition.display_name, function(input)
    M.changeNamespace(input)
  end, { header = { data = {} }, prompt = true })

  local self = ResourceBuilder:new(M.definition.resource)
  self.definition = M.definition

  commands.run_async(
    "get_resources_async",
    { M.definition.gvk.k, M.definition.gvk.g, M.definition.gvk.v, nil, nil },
    function(data)
      self.data = data
      self:decodeJson()
      vim.schedule(function()
        self.buf_nr = buf
        self:process(definition.processRow, true):prettyPrint():setContent()
        local list = { { name = "All" } }
        for _, value in ipairs(self.processedData) do
          if value.name.value then
            table.insert(M.namespaces, value.name.value)
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
    end
  )
end

--- Returns a list of namespaces
--- @return string[]
function M.listNamespaces()
  if #M.namespaces - #config.options.namespace_fallback > 1 then
    return M.namespaces
  end
  local output = commands.shell_command("kubectl", { "get", "ns", "-o", "name", "--no-headers" })
  local ns = {}
  for line in output:gmatch("[^\r\n]+") do
    local namespace = line:match("^namespace/(.+)$")
    if namespace then
      table.insert(ns, namespace)
    end
  end

  M.namespaces = ns
  return M.namespaces
end

function M.changeNamespace(name)
  if name == "" then
    name = "All"
  end
  state.ns = name
  if name ~= "All" then
    commands.shell_command("kubectl", { "config", "set-context", "--current", "--namespace=" .. name })
  end
end

return M
