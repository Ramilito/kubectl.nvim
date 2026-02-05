local BaseResource = require("kubectl.resources.base_resource")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")

local resource = "cronjobs"

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "batch", v = "v1", k = "CronJob" },
  child_view = {
    name = "jobs",
    predicate = function(name)
      return "metadata.ownerReferences.name=" .. name
    end,
  },
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
})

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
      hl = hl.symbols.pending,
    },
    {
      text = "dry run:",
      value = "false",
      type = "flag",
      hl = hl.symbols.pending,
    },
  }

  builder.action_view(create_def, data, function(args)
    local job_name = args[1].value
    local dry_run = args[2].value == "true" and true or false

    local client = require("kubectl.client")
    local status = client.create_job_from_cronjob(job_name, ns, name, dry_run)
    if status then
      vim.notify(status)
    end
  end)
end

return M
