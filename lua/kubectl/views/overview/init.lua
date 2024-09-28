local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.overview.definition")
local grid = require("kubectl.utils.grid")
local url = require("kubectl.utils.url")

local M = {
  handles = nil,
}

function M.View(cancellationToken)
  if M.handles then
    return
  end
  local cmds = {
    {
      cmd = "curl",
      args = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/nodes?pretty=false" },
    },
    {
      cmd = "curl",
      args = { "{{BASE}}/api/v1/nodes?pretty=false" },
    },
    {
      cmd = "curl",
      args = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/{{NAMESPACE}}pods?pretty=false" },
    },
    { cmd = "curl", args = { "{{BASE}}/api/v1/{{NAMESPACE}}pods?pretty=false" } },
    { cmd = "curl", args = { "{{BASE}}/apis/apps/v1/{{NAMESPACE}}replicasets?pretty=false" } },
    { cmd = "curl", args = { "{{BASE}}/api/v1/{{NAMESPACE}}events?pretty=false" } },
  }

  for _, cmd in ipairs(cmds) do
    if cmd.cmd == "curl" then
      cmd.args = url.build(cmd.args)
      cmd.args = url.addHeaders(cmd.args, cmd.contentType)
    else
    end
  end

  M.handles = commands.await_shell_command_async(cmds, function(data)
    local builder = ResourceBuilder:new(definition.resource)
    builder.data = data

    vim.schedule(function()
      builder:decodeJson():process(definition.processRow, true)
      if builder.processedData then
        builder.prettyData, builder.extmarks = grid.pretty_print(builder.processedData, definition.getSections())
        builder:addHints(definition.hints, true, true, true)
        if cancellationToken and cancellationToken() then
          return nil
        end

        builder:display(definition.ft, definition.resource)
        builder:setContent(nil)
        M.handles = nil
      end
    end)
  end)
end

return M
