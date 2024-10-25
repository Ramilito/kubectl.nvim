local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.jobs.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  definition.owner = {}
  definition.display_name = "Jobs"
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if definition.owner.name then
    definition.display_name = "Jobs" .. "(" .. definition.owner.ns .. "/" .. definition.owner.name .. ")"
  end
  state.instance:draw(definition, cancellationToken)
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "jobs_desc_" .. name .. "_" .. ns,
    ft = "k8s_desc",
    url = { "describe", "job", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

function M.create_from_job(name, ns)
  local builder = ResourceBuilder:new("kubectl_create_job")

  local create_def = {
    ft = "k8s_create_job",
    display = string.format("create job from job: %s/%s?", ns, name),
    resource = name,
    cmd = { "create", "job", "--from", "jobs/" .. name, "-n", ns },
  }
  local unix_time = os.time()
  local data = {
    { text = "name:", value = name .. "-" .. tostring(unix_time), cmd = "" },
    { text = "dry run:", enum = { "none", "server", "client" }, cmd = "--dry-run" },
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
