local BaseResource = require("kubectl.resources.base_resource")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")

local resource = "secrets"

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "Secret" },
  informer = { enabled = true },
  headers = {
    "NAMESPACE",
    "NAME",
    "TYPE",
    "DATA",
    "AGE",
  },
})

-- Override Yaml with hints for base64 decode
function M.Yaml(name, ns)
  local title = M.definition.resource .. " | " .. name .. " | " .. ns

  local def = {
    resource = M.definition.resource .. "_yaml",
    ft = "k8s_" .. M.definition.resource .. "_yaml",
    title = title,
    syntax = "yaml",
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "base64decode" },
    },
    panes = {
      { title = "YAML" },
    },
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_framed(def)
  builder.renderHints()

  vim.api.nvim_set_option_value("syntax", "yaml", { buf = builder.buf_nr })

  commands.run_async("get_single_async", {
    gvk = M.definition.gvk,
    namespace = ns,
    name = name,
    output = "yaml",
  }, function(result)
    if not result then
      return
    end
    vim.schedule(function()
      local lines = vim.split(result, "\n", { plain = true })
      buffers.set_content(builder.buf_nr, {
        content = lines,
        header = { data = {}, marks = {} },
      })
    end)
  end)
end

return M
