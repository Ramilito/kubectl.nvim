local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.cronjobs.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "cronjobs | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "cronjob", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

function M.create_from_cronjob(name, ns)
  local builder = ResourceBuilder:new("kubectl_create_job")

  local create_def = {
    ft = "k8s_create_job",
    display = string.format("create job from cronjob: %s/%s?", ns, name),
    resource = name,
    cmd = { "create", "job", "--from", "cronjobs/" .. name, "-n", ns },
  }
  local unix_time = os.time()
  local data = {
    {
      text = "name:",
      value = name .. "-" .. tostring(unix_time),
      type = "positional",
    },
    {
      text = "dry run:",
      value = "none",
      options = { "none", "server", "client" },
      cmd = "--dry-run",
      type = "option",
    },
  }

  builder:action_view(create_def, data, function(args)
    commands.shell_command_async("kubectl", args, function(response)
      vim.schedule(function()
        vim.notify(response)
      end)
    end)
  end)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
