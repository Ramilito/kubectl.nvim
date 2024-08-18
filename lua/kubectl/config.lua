local M = {}

---@class KubectlOptions
---@field auto_refresh { enabled: boolean, interval: number }
---@field namespace string
---@field notifications { enabled: boolean, verbose: boolean, blend: number }
---@field hints boolean
---@field context boolean
---@field float_size { width: number, height: number, col: number, row: number }
---@field obj_fresh number
---@field mappings { exit: string }
local defaults = {
  auto_refresh = {
    enabled = true,
    interval = 3000, -- milliseconds
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
  mappings = {
    exit = "<leader>k",
  },
  custom_views = {},
}

---@type KubectlOptions
M.options = vim.deepcopy(defaults)

--- Setup kubectl options
--- @param options KubectlOptions The configuration options for kubectl
function M.setup(options)
  M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

return M
