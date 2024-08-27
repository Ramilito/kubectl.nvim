local M = {}
local str = require("kubectl.utils.string")

---@class KubectlOptions
---@field auto_refresh { enabled: boolean, interval: number }
---@field namespace string
---@field notifications { enabled: boolean, verbose: boolean, blend: number }
---@field hints boolean
---@field context boolean
---@field float_size { width: number, height: number, col: number, row: number }
---@field obj_fresh number
---@field keymaps { }
---@field mappings { } deprecated
local defaults = {
  auto_refresh = {
    enabled = true,
    interval = 300, -- milliseconds
  },
  diff = {
    bin = "kubediff",
  },
  namespace = "All",
  namespace_fallback = {},
  notifications = {
    enabled = true,
    verbose = false,
    blend = 100,
  },
  hints = true,
  context = true,
  float_size = {
    -- Almost fullscreen:
    -- width = 1.0,
    -- height = 0.95, -- Setting it to 1 will be cutoff by statuscolumn

    -- For more context aware size:
    width = 0.9,
    height = 0.8,
    col = 10,
    row = 5,
  },
  obj_fresh = 0, -- highghlight if age is less than minutes
  ---@type table<'global'|'views'|'deployments'|'containers'|'crds'|'cronjobs', table>
  keymaps = {
    global = {
      help = { key = "g?", desc = "help" },
      go_up = { key = "<bs>", desc = "go-up" },
      view_pfs = { key = "gP", desc = "port-forwards" },
      delete = { key = "gD", desc = "delete", long_desc = "Delete resource" },
      describe = { key = "gd", desc = "describe", long_desc = "Describe resource" },
      edit = { key = "ge", desc = "edit", long_desc = "Edit resource" },
      reload = { key = "gr", desc = "reload", long_desc = "Reload view" },
      sort = { key = "gs", desc = "sort", long_desc = "Sort by column" },
      namespaces = { key = "<C-n>", desc = "change-ns", long_desc = "Change namespace" },
      filter = { key = "<C-f>", desc = "filter", long_desc = "Filter on a phrase" },
      aliases = { key = "<C-a>", desc = "aliases", long_desc = "Aliases view" },
    },
    views = {
      deployments = { key = "1", desc = "Deployments view" },
      pods = { key = "2", desc = "Pods view" },
      configmaps = { key = "3", desc = "Configmaps view" },
      secrets = { key = "4", desc = "Secrets view" },
      services = { key = "5", desc = "Services view" },
    },
    deployments = {
      view_pods = { key = "<CR>", desc = "pods", long_desc = "Go to pods of deployment" },
      set_image = { key = "gi", desc = "set-image", long_desc = "Set image for deployment" },
      restart = { key = "grr", desc = "restart", long_desc = "Restart deployment" },
      scale = { key = "<C-s>", desc = "scale", long_desc = "Scale deployment" },
    },
    daemonsets = {
      view_pods = { key = "<CR>", desc = "pods", long_desc = "Go to pods of daemonset" },
      restart = { key = "<grr>", desc = "restart", long_desc = "Rollout restart selected daemonset" },
      set_image = { key = "<gi>", desc = "set image", long_desc = "Set image for selected daemonset" },
      { key = "<enter>", desc = "pods", long_desc = "Opens pods view" },
    },
    containers = {
      exec = { key = "<CR>", desc = "exec", long_desc = "Exec into container" },
      logs = {
        view = { key = "gl", desc = "view" },
        follow = { key = "f", desc = "follow" },
        wrap = { key = "gw", desc = "wrap" },
      },
    },
    crds = {
      view = { key = "<CR>", desc = "view-resource", long_desc = "Go to resource view" },
    },
    cronjobs = {
      view_jobs = { key = "<CR>", desc = "view-jobs", long_desc = "View jobs of cronjob" },
      create = { key = "gc", desc = "create-job", long_desc = "Create new job for cronjob" },
      toggle_suspend = { key = "gx", desc = "toggle-suspend", long_desc = "Toggle suspend cronjob" },
    },
    events = {
      view_message = { key = "<CR>", desc = "view-message", long_desc = "View message" },
    },
    jobs = {
      view_pods = { key = "<CR>", desc = "pods", long_desc = "Go to pods of job" },
      create = { key = "gc", desc = "create-job", long_desc = "Create new job from job" },
    },
    nodes = {
      drain = { key = "gR", desc = "drain", long_desc = "Drain node" },
      uncordon = { key = "gU", desc = "uncordon", long_desc = "Uncordon node" },
      cordon = { key = "gC", desc = "cordon", long_desc = "Cordon node" },
    },
    pods = {
      logs = {
        view = { key = "gl", desc = "logs", long_desc = "Open logs" },
        follow = { key = "f", desc = "follow" },
        wrap = { key = "gw", desc = "wrap", long_desc = "Wrap log lines" },
      },
    },
  },
}

---@type KubectlOptions
M.options = vim.deepcopy(defaults)

--- Setup kubectl options
--- @param options KubectlOptions The configuration options for kubectl
function M.setup(options)
  if options and options.mappings and options.mappings.exit then
    vim.notify("Warning: mappings.exit is deprecated. Please use own mapping to call require('kubectl').close()")
  end
  M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

function M.get_desc(k, short)
  if k.long_desc and not short then
    return k.long_desc
  end
  if k.desc then
    return str.capitalize(k.desc)
  end
  return ""
end

return M
