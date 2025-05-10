local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "cronjobs"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "batch", v = "v1", k = "CronJob" },
    hints = {
      { key = "<Plug>(kubectl.create_job)", desc = "create", long_desc = "Create job from cronjob" },
      { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
      { key = "<Plug>(kubectl.suspend_cronjob)", desc = "suspend", long_desc = "Suspend/Unsuspend cronjob" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "SCHEDULE",
      "SUSPEND",
      "ACTIVE",
      "LAST SCHEDULE",
      "AGE",
      "CONTAINERS",
      "IMAGES",
      "SELECTOR",
    },
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    builder.draw(cancellationToken)
  end
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = "cronjobs | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }
  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      context = state.context["current-context"],
      gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = ns,
      name = name,
    },
    reload = reload,
  })
end

function M.create_from_cronjob(name, ns)
  local builder = manager.get_or_create("kubectl_create_job")

  local create_def = {
    ft = "k8s_action",
    display = string.format("create job from cronjob: %s/%s?", ns, name),
    resource = name,
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
      value = "false",
      type = "flag",
    },
  }

  builder.action_view(create_def, data, function(args)
    local job_name = args[1].value
    local dry_run = args[2].value == "true" and true or false

    vim.print(dry_run)
    local client = require("kubectl.client")
    local status = client.create_job_from_cronjob(job_name, ns, name, dry_run)
    if status then
      vim.notify(status)
    end
  end)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
