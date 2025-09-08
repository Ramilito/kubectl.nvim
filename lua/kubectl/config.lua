local M = {
  config_did_setup = false,
}

---@alias SkewConfig { enabled: boolean, log_level: number }
---@alias AutoRefreshConfig { enabled: boolean, interval: number }
---@alias DiffConfig { bin: string }
---@alias KubectlCmd { cmd: string, env: table<string, string>, args: string[], persist_context_change: boolean }
-- luacheck: no max line length
---@alias HeadersConfig { enabled: boolean, blend: integer, hints: boolean, context: boolean, heartbeat: boolean, skew: SkewConfig }
---@alias LineageConfig { enabled: boolean }
---@alias CompletionConfig { follow_cursor: boolean }
---@alias LogsConfig { prefix: boolean, timestamps: boolean, since: string }
---@alias AliasConfig { apply_on_select_from_history: boolean, max_history: number }
---@alias FilterConfig { apply_on_select_from_history: boolean, max_history: number }
---@alias FilterLabelConfig { max_history: number }
---@alias FloatSizeConfig { width: number, height: number, col: number, row: number }
---@alias StatuslineConfig { enabled: boolean }

---@class KubectlOptions
---@field log_level number
---@field auto_refresh AutoRefreshConfig
---@field diff DiffConfig
---@field kubectl_cmd KubectlCmd
---@field terminal_cmd string?
---@field namespace string
---@field namespace_fallback string[]
---@field headers HeadersConfig
---@field lineage LineageConfig
---@field completion CompletionConfig
---@field logs LogsConfig
---@field alias AliasConfig
---@field filter FilterConfig
---@field filter_label FilterLabelConfig
---@field float_size FloatSizeConfig
---@field statusline StatuslineConfig
---@field obj_fresh number
---@field api_resources_cache_ttl number

---@type KubectlOptions
local defaults = {
  log_level = vim.log.levels.INFO,
  auto_refresh = {
    enabled = true,
    interval = 500, -- milliseconds
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
    blend = 20,
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
  filter_label = {
    max_history = 20,
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
  statusline = {
    enabled = false,
  },
  obj_fresh = 5, -- highlight if age is less than minutes
  api_resources_cache_ttl = 60 * 60 * 3,
}

---@type KubectlOptions
M.options = vim.deepcopy(defaults)

--- Setup kubectl options
---@param options KubectlOptions? The configuration options for kubectl (optional)
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
  M.config_did_setup = true
end

return M
