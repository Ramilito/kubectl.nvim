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

  builder.action_view(create_def, data, function(args)
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
