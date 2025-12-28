local M = {
  config_did_setup = false,
}

--- Schema definition for config validation
--- Each field can have: type, enum, min, max, schema (for nested tables)
---@alias SchemaField { type: string, enum: table?, min: number?, max: number?, schema: table?, optional: boolean? }
---@alias Schema table<string, SchemaField>

---@type Schema
local schema = {
  log_level = {
    type = "number",
    enum = {
      vim.log.levels.DEBUG,
      vim.log.levels.ERROR,
      vim.log.levels.INFO,
      vim.log.levels.OFF,
      vim.log.levels.TRACE,
      vim.log.levels.WARN,
    },
  },
  auto_refresh = {
    type = "table",
    schema = {
      enabled = { type = "boolean" },
      interval = { type = "number", min = 100 },
    },
  },
  diff = {
    type = "table",
    schema = {
      bin = { type = "string" },
    },
  },
  kubectl_cmd = {
    type = "table",
    schema = {
      cmd = { type = "string" },
      env = { type = "table" },
      args = { type = "table" },
      persist_context_change = { type = "boolean" },
    },
  },
  terminal_cmd = { type = "string", optional = true },
  namespace = { type = "string" },
  namespace_fallback = { type = "table" },
  headers = {
    type = "table",
    schema = {
      enabled = { type = "boolean" },
      hints = { type = "boolean" },
      context = { type = "boolean" },
      heartbeat = { type = "boolean" },
      blend = { type = "number", min = 0, max = 100 },
      skew = {
        type = "table",
        schema = {
          enabled = { type = "boolean" },
          log_level = {
            type = "number",
            enum = {
              vim.log.levels.DEBUG,
              vim.log.levels.ERROR,
              vim.log.levels.INFO,
              vim.log.levels.OFF,
              vim.log.levels.TRACE,
              vim.log.levels.WARN,
            },
          },
        },
      },
    },
  },
  lineage = {
    type = "table",
    schema = {
      enabled = { type = "boolean" },
    },
  },
  completion = {
    type = "table",
    schema = {
      follow_cursor = { type = "boolean" },
    },
  },
  logs = {
    type = "table",
    schema = {
      prefix = { type = "boolean" },
      timestamps = { type = "boolean" },
      since = { type = "string" },
    },
  },
  alias = {
    type = "table",
    schema = {
      apply_on_select_from_history = { type = "boolean" },
      max_history = { type = "number", min = 0 },
    },
  },
  filter = {
    type = "table",
    schema = {
      apply_on_select_from_history = { type = "boolean" },
      max_history = { type = "number", min = 0 },
    },
  },
  filter_label = {
    type = "table",
    schema = {
      max_history = { type = "number", min = 0 },
    },
  },
  float_size = {
    type = "table",
    schema = {
      width = { type = "number", min = 0 },
      height = { type = "number", min = 0 },
      col = { type = "number", min = 0 },
      row = { type = "number", min = 0 },
    },
  },
  statusline = {
    type = "table",
    schema = {
      enabled = { type = "boolean" },
    },
  },
  obj_fresh = { type = "number", min = 0 },
  api_resources_cache_ttl = { type = "number", min = 0 },
}

--- Validate a config value against a schema field
---@param value any The value to validate
---@param field_schema SchemaField The schema for this field
---@param path string The path to this field (for error messages)
---@return string[] errors List of validation errors
local function validate_field(value, field_schema, path)
  local errors = {}

  -- Handle nil values - not an error, will use default value
  if value == nil then
    return errors
  end

  -- Type validation
  local actual_type = type(value)
  if actual_type ~= field_schema.type then
    table.insert(errors, string.format("%s: expected %s, got %s", path, field_schema.type, actual_type))
    return errors -- Skip further validation if type is wrong
  end

  -- Enum validation
  if field_schema.enum then
    local valid = false
    for _, enum_val in ipairs(field_schema.enum) do
      if value == enum_val then
        valid = true
        break
      end
    end
    if not valid then
      local enum_str = table.concat(vim.tbl_map(tostring, field_schema.enum), ", ")
      table.insert(errors, string.format("%s: invalid value %s, expected one of: %s", path, tostring(value), enum_str))
    end
  end

  -- Number range validation
  if field_schema.type == "number" then
    if field_schema.min and value < field_schema.min then
      table.insert(errors, string.format("%s: value %s is below minimum %s", path, value, field_schema.min))
    end
    if field_schema.max and value > field_schema.max then
      table.insert(errors, string.format("%s: value %s is above maximum %s", path, value, field_schema.max))
    end
  end

  -- Nested table validation
  if field_schema.type == "table" and field_schema.schema then
    for key, nested_schema in pairs(field_schema.schema) do
      local nested_errors = validate_field(value[key], nested_schema, path .. "." .. key)
      for _, err in ipairs(nested_errors) do
        table.insert(errors, err)
      end
    end
  end

  return errors
end

--- Validate user config against the schema
---@param options table? The user-provided config options
---@return boolean valid Whether the config is valid
---@return string[] errors List of validation errors
local function validate_config(options)
  if options == nil then
    return true, {}
  end

  if type(options) ~= "table" then
    return false, { "config: expected table, got " .. type(options) }
  end

  local errors = {}

  for key, value in pairs(options) do
    local field_schema = schema[key]
    if field_schema then
      local field_errors = validate_field(value, field_schema, key)
      for _, err in ipairs(field_errors) do
        table.insert(errors, err)
      end
    end
    -- Note: unknown keys are allowed (for forward compatibility)
  end

  return #errors == 0, errors
end

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
  -- Validate config before merging
  local valid, errors = validate_config(options)
  if not valid then
    local msg = "kubectl.nvim: Invalid config:\n  " .. table.concat(errors, "\n  ")
    vim.notify(msg, vim.log.levels.ERROR)
    -- Continue with defaults for invalid fields - they won't be merged
  elseif #errors > 0 then
    -- Warnings (if we add warning-level validations in the future)
    local msg = "kubectl.nvim: Config warnings:\n  " .. table.concat(errors, "\n  ")
    vim.notify(msg, vim.log.levels.WARN)
  end

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
