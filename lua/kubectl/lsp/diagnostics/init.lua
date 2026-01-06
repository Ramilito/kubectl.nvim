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

--- Build diagnostic message from row data
---@param row table
---@return string
local function get_message(row)
  local parts = {}

  if row.status then
    local val = get_value(row.status)
    if val ~= "" and val ~= "Running" and val ~= "Succeeded" and val ~= "Active" then
      table.insert(parts, val)
    end
  end

  if row.restarts then
    local val = get_value(row.restarts)
    if val and tonumber(val) and tonumber(val) > 0 then
      table.insert(parts, val .. " restarts")
    end
  end

  if row.ready then
    local val = get_value(row.ready)
    if val and val:match("^%d+/%d+$") then
      local current, total = val:match("^(%d+)/(%d+)$")
      if current ~= total then
        table.insert(parts, "Ready: " .. val)
      end
    end
  end

  return table.concat(parts, " | ")
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
      local name = get_value(row.name)
      local namespace = get_value(row.namespace)
      local message = get_message(row)

      local text = name
      if namespace ~= "" then
        text = namespace .. "/" .. name
      end
      if message ~= "" then
        text = text .. ": " .. message
      end

      table.insert(diagnostics, {
        lnum = content_start + i - 1, -- 0-indexed
        col = 0,
        message = text,
        severity = severity,
        source = "kubectl",
      })
    end
  end

  vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- Send diagnostics to quickfix
function M.to_quickfix()
  vim.diagnostic.setqflist({ namespace = ns, title = "Kubectl Issues" })
  vim.cmd("copen")
end

--- Setup diagnostics
function M.setup()
  -- Configure our diagnostic namespace
  vim.diagnostic.config({
    virtual_text = {
      prefix = "●",
      spacing = 2,
    },
    signs = false,
    underline = true,
    update_in_insert = false,
  }, ns)

  -- Set diagnostics when data loads
  vim.api.nvim_create_autocmd("User", {
    pattern = "K8sDataLoaded",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local ft = vim.bo[bufnr].filetype

      if not ft or not ft:match("^k8s_") then
        return
      end

      -- Skip non-resource filetypes
      local skip = {
        k8s_filter = true,
        k8s_namespaces = true,
        k8s_contexts = true,
        k8s_aliases = true,
        k8s_pod_logs = true,
        k8s_action = true,
      }
      if skip[ft] or ft:match("_yaml$") or ft:match("_describe$") then
        return
      end

      local resource = ft:match("^k8s_(.+)$")
      if resource then
        M.set_diagnostics(bufnr, resource)
      end
    end,
  })
end

return M
