local M = {}

---@alias SkewConfig { enabled: boolean, log_level: number }
---@alias HeadersConfig { enabled: boolean, hints: boolean, context: boolean, heartbeat: boolean, skew: SkewConfig }

---@class KubectlOptions
---@field log_level number
---@field auto_refresh { enabled: boolean, interval: number }
---@field terminal_cmd string?
---@field namespace string
---@field namespace_fallback string[]
---@field headers HeadersConfig
---@field hints boolean
---@field context boolean
---@field heartbeat boolean
---@field lineage { enabled: boolean }
---@field completion { follow_cursor: boolean }
---@field logs { prefix: boolean, timestamps: boolean, since: string }
---@field float_size { width: number, height: number, col: number, row: number }
---@field obj_fresh number
local defaults = {
  log_level = vim.log.levels.INFO,
  auto_refresh = {
    enabled = true,
    interval = 2000, -- milliseconds
  },
  diff = {
    bin = "kubediff",
  },
  -- We will use this when invoking kubectl.
  -- The subshells invoked will have PATH, HOME and the environments listed below
  -- NOTE: Some executions using the io.open and vim.fn.terminal will still have default shell environments,
  -- in that case, the environments below will not override the defaults and should not be in your .zshrc/.bashrc files
  kubectl_cmd = { cmd = "kubectl", env = {}, args = {}, persist_context_change = false },
  terminal_cmd = nil, -- Exec will launch in a terminal if set, i.e. "ghostty -e"
  namespace = "All",
  namespace_fallback = {},
  headers = {
    enabled = true,
    hints = true,
    context = true,
    heartbeat = true,
    skew = {
      enabled = true,
      log_level = vim.log.levels.OFF,
    },
  },
  lineage = {
    enabled = true,
  },
  completion = {
    follow_cursor = false,
  },
  logs = {
    prefix = true,
    timestamps = true,
    since = "5m",
  },
  alias = {
    apply_on_select_from_history = true,
    max_history = 5,
  },
  filter = {
    apply_on_select_from_history = true,
    max_history = 10,
  },
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
  obj_fresh = 5, -- highghlight if age is less than minutes
}

---@type KubectlOptions
M.options = vim.deepcopy(defaults)

--- Setup kubectl options
--- @param options KubectlOptions The configuration options for kubectl
function M.setup(options)
  ---@diagnostic disable-next-line: undefined-field
  if options and options.mappings and options.mappings.exit then
    vim.notify("Warning: mappings.exit is deprecated. Please use own mapping to call require('kubectl').close()")
  end

  ---@diagnostic disable-next-line: undefined-field
  if options and options.notifications then
    vim.notify("Warning: notifications is deprecated. This feature is removed")
  end
  M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

return M
