local M = {}

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
      help = { lhs = "g?", desc = "Help" },
      go_up = { lhs = "<bs>", desc = "Go up" },
      view_pf = { lhs = "gP", desc = "Port forwards" },
      delete = { lhs = "gD", desc = "Delete resource" },
      describe = { lhs = "gd", desc = "Describe resource" },
      edit = { lhs = "ge", desc = "Edit resource" },
      reload = { lhs = "gr", desc = "Reload view" },
      sort = { lhs = "gs", desc = "Sort column" },
      namespaces = { lhs = "<C-n>", desc = "Change namespace" },
      filter = { lhs = "<C-f>", desc = "Filter on a phrase" },
      aliases = { lhs = "<C-a>", desc = "Aliases" },
    },
    views = {
      deployments = { lhs = "1", desc = "Deployments view" },
      pods = { lhs = "2", desc = "Pods view" },
      configmaps = { lhs = "3", desc = "Configmaps view" },
      secrets = { lhs = "4", desc = "Secrets view" },
      services = { lhs = "5", desc = "Services view" },
    },
    deployments = {
      view_pods = { lhs = "<CR>", desc = "pods", long_desc = "Go to pods of deployment" },
      set_image = { lhs = "gi", desc = "Set image" },
      restart = { lhs = "grr" },
      scale = { lhs = "<C-s>" },
    },
    containers = {
      exec = { lhs = "<CR>" },
      logs = {
        view = { lhs = "gl" },
        follow = { lhs = "f" },
        wrap = { lhs = "gw" },
      },
    },
    crds = {
      view = { lhs = "<CR>" },
    },
    cronjobs = {
      view_jobs = { lhs = "<CR>" },
      create = { lhs = "gc" },
      toggle_suspend = { lhs = "gx" },
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

return M
