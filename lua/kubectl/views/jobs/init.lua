local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
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

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_job_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "jobs/" .. name, "-n", ns })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
