local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.lineage.definition")
local logger = require("kubectl.utils.logging")

local M = { handles = nil }

local owners = {}
local function get_owners(ownerReferences)
  for _, owner in pairs(ownerReferences) do
    table.insert(owners, { uid = owner.uid, name = owner.kind, kind = owner.kind, apiVersion = owner.apiVersion })
  end
end

function M.View(name, ns, kind)
  local parsed_input = string.lower(vim.trim(kind))

  local ok, view_def = pcall(require, "kubectl.views." .. parsed_input .. ".definition")
  if not ok then
    return nil
  end
  local url = view_def.url_base .. "/" .. name .. "?pretty=false"

  if ns then
    url = url:gsub("{{NAMESPACE}}", string.format("namespaces/%s/", ns))
  end
  view_def.url = { url }
  ResourceBuilder:new(view_def.resource):setCmd({ url }, "curl"):fetchAsync(function(self)
    self:decodeJson()
    get_owners(self.data.metadata.ownerReferences)

    logger.notify_table(owners)
  end)
  -- commands.shell_command_async(cmds, function(data) end)

  -- local cmds = {
  --   { cmd = "curl", args = { "{{BASE}}/api/v1/{{NAMESPACE}}pods?pretty=false" } },
  --   { cmd = "curl", args = { "{{BASE}}/apis/apps/v1/{{NAMESPACE}}replicasets?pretty=false" } },
  --   { cmd = "curl", args = { "{{BASE}}/api/v1/{{NAMESPACE}}deployments?pretty=false" } },
  -- }
  --
  -- for _, cmd in ipairs(cmds) do
  --   if cmd.cmd == "curl" then
  --     cmd.args = url.build(cmd.args)
  --     cmd.args = url.addHeaders(cmd.args, cmd.contentType)
  --   else
  --   end
  -- end
  --
  -- M.handles = commands.await_shell_command_async(cmds, function(data)
  --   local builder = ResourceBuilder:new(definition.resource)
  --   builder.data = data
  --   vim.schedule(function()
  --     builder:decodeJson():process(definition.processRow, true)
  --   end)
  -- end)
end

return M
