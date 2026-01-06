local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local M = {}

-- Diagnostic namespace for kubectl
local ns = vim.api.nvim_create_namespace("kubectl_diagnostics")

-- Status symbols that indicate problems
local error_symbols = { KubectlError = vim.diagnostic.severity.ERROR }
local warning_symbols = { KubectlWarning = vim.diagnostic.severity.WARN }

--- Get severity from a status symbol
---@param symbol string|nil
---@return integer|nil
local function get_severity(symbol)
  if not symbol then
    return nil
  end
  if error_symbols[symbol] then
    return error_symbols[symbol]
  end
  if warning_symbols[symbol] then
    return warning_symbols[symbol]
  end
  return nil
end

--- Extract value from field (handles both table and string)
---@param field any
---@return string
local function get_value(field)
  if type(field) == "table" then
    return field.value or ""
  end
  return field or ""
end

--- Status descriptions for common Kubernetes states
local status_hints = {
  CrashLoopBackOff = "Container keeps crashing after restart attempts",
  ImagePullBackOff = "Failed to pull container image, check image name/registry access",
  ErrImagePull = "Error pulling container image",
  CreateContainerConfigError = "Invalid container configuration",
  InvalidImageName = "Container image name is malformed",
  OOMKilled = "Container exceeded memory limit and was killed",
  Error = "Container exited with an error",
  Completed = "Container finished execution",
  ContainerCreating = "Container is being created",
  PodInitializing = "Init containers are running",
  Pending = "Pod is waiting to be scheduled",
  Terminating = "Pod is being terminated",
  Evicted = "Pod was evicted from node (resource pressure)",
  Unknown = "Pod state cannot be determined",
  ContainerStatusUnknown = "Container status cannot be determined",
  ["Init:ContainerStatusUnknown"] = "Init container status cannot be determined",
  ["Init:ErrImagePull"] = "Init container failed to pull image",
  ["Init:ImagePullBackOff"] = "Init container image pull back-off",
}

--- Build diagnostic message from row data
---@param row table
---@param severity integer
---@return string
local function get_message(row, severity)
  local parts = {}

  -- Status with hint
  if row.status then
    local val = get_value(row.status)
    if val ~= "" and val ~= "Running" and val ~= "Succeeded" and val ~= "Active" then
      local hint = status_hints[val]
      if hint then
        table.insert(parts, string.format("%s - %s", val, hint))
      else
        table.insert(parts, val)
      end
    end
  end

  -- Ready count
  if row.ready then
    local val = get_value(row.ready)
    if val and val:match("^%d+/%d+$") then
      local current, total = val:match("^(%d+)/(%d+)$")
      if current ~= total then
        table.insert(parts, string.format("Ready: %s/%s containers", current, total))
      end
    end
  end

  -- Restarts with context
  if row.restarts then
    local val = get_value(row.restarts)
    -- Handle "5 (2m ago)" format
    local count = val and val:match("^(%d+)")
    if count and tonumber(count) > 0 then
      table.insert(parts, string.format("Restarts: %s", val))
    end
  end

  -- Age for context
  if row.age and severity == vim.diagnostic.severity.ERROR then
    local age = get_value(row.age)
    if age ~= "" then
      table.insert(parts, string.format("Age: %s", age))
    end
  end

  return table.concat(parts, " │ ")
end

--- Set diagnostics for a resource buffer
---@param bufnr number
---@param resource string
function M.set_diagnostics(bufnr, resource)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local builder = manager.get(resource)
  if not builder or not builder.processedData then
    return
  end

  local buf_state = state.get_buffer_state(bufnr)
  local content_start = buf_state.content_row_start or 1

  local diagnostics = {}

  for i, row in ipairs(builder.processedData) do
    local severity = nil

    if row.status and type(row.status) == "table" then
      severity = get_severity(row.status.symbol)
    end
    if not severity and row.phase and type(row.phase) == "table" then
      severity = get_severity(row.phase.symbol)
    end
    if not severity and row.conditions and type(row.conditions) == "table" then
      severity = get_severity(row.conditions.symbol)
    end

    if severity then
      local message = get_message(row, severity)

      if message ~= "" then
        table.insert(diagnostics, {
          lnum = content_start + i - 1, -- 0-indexed
          col = 0,
          message = message,
          severity = severity,
          source = "kubectl",
        })
      end
    end
  end

  vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- Send diagnostics to quickfix
function M.to_quickfix()
  vim.diagnostic.setqflist({ namespace = ns, title = "Kubectl Issues" })
  vim.cmd("copen")
end

local diagnostics_enabled = true

--- Toggle diagnostic display on/off
function M.toggle()
  diagnostics_enabled = not diagnostics_enabled

  if diagnostics_enabled then
    vim.diagnostic.config({
      virtual_lines = { current_line = true },
    })
    vim.notify("Diagnostics: on", vim.log.levels.INFO)
  else
    vim.diagnostic.config({
      virtual_lines = false,
    })
    vim.notify("Diagnostics: off", vim.log.levels.INFO)
  end
end

--- Setup diagnostics
function M.setup()
  vim.diagnostic.config({
    virtual_text = false,
    virtual_lines = { current_line = true },
    signs = true,
    underline = false,
    update_in_insert = false,
  })
end

return M
