local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

-- Request ID for cancelling stale hover requests
local current_request_id = 0

--- Get diagnostic section for current line
---@param bufnr number
---@param line number 0-indexed line number
---@return string|nil markdown formatted diagnostic section
local function get_diagnostic_section(bufnr, line)
  local diags = vim.diagnostic.get(bufnr, { lnum = line })
  if #diags == 0 then
    return nil
  end

  local lines = { "", "---", "## Diagnostics" }
  for _, diag in ipairs(diags) do
    local severity = vim.diagnostic.severity[diag.severity] or "INFO"
    -- Colored circle emojis provide clear visual severity distinction in hover
    local icon = diag.severity == vim.diagnostic.severity.ERROR and "🔴"
      or diag.severity == vim.diagnostic.severity.WARN and "🟡"
      or "🔵"
    table.insert(lines, string.format("%s **%s**: %s", icon, severity, diag.message))
  end

  return table.concat(lines, "\n")
end

--- Extract resource name from filetype (k8s_pods -> pods)
---@param ft string
---@return string|nil
local function resource_from_filetype(ft)
  if not ft or not ft:match("^k8s_") then
    return nil
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
  if skip[ft] then
    return nil
  end
  -- Also skip yaml/describe views
  if ft:match("_yaml$") or ft:match("_describe$") then
    return nil
  end
  return ft:match("^k8s_(.+)$")
end

--- Get current selection from buffer using builder's column config
---@param builder table
---@return string|nil name
---@return string|nil namespace
local function get_selection(builder)
  if not builder or not builder.definition then
    return nil, nil
  end

  local def = builder.definition
  local name_col, ns_col = tables.getColumnIndices(builder.resource, def.headers or {})

  if not name_col then
    return nil, nil
  end

  -- Check if cursor is on content row
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = state.get_buffer_state(bufnr)
  if not buf_state or not buf_state.content_row_start then
    return nil, nil
  end

  local line_number = vim.api.nvim_win_get_cursor(0)[1]
  if line_number <= buf_state.content_row_start then
    return nil, nil
  end

  if ns_col then
    return tables.getCurrentSelection(name_col, ns_col)
  else
    return tables.getCurrentSelection(name_col), nil
  end
end

--- Handle hover request
---@param _params table LSP hover params (unused, cursor position used instead)
---@param callback function LSP callback
function M.get_hover(_params, callback)
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local resource = resource_from_filetype(ft)

  if not resource then
    callback(nil, nil)
    return
  end

  local builder = manager.get(resource)
  if not builder or not builder.definition then
    callback(nil, nil)
    return
  end

  local name, ns = get_selection(builder)
  if not name then
    callback(nil, nil)
    return
  end

  local gvk = builder.definition.gvk
  if not gvk then
    callback(nil, nil)
    return
  end

  -- Capture cursor position before async call
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

  -- Increment request ID to cancel stale requests
  current_request_id = current_request_id + 1
  local request_id = current_request_id

  -- Fetch and format resource data via Rust
  commands.run_async("get_hover_async", {
    gvk = gvk,
    namespace = ns,
    name = name,
  }, function(content)
    vim.schedule(function()
      -- Check if this request is stale (newer request was made)
      if request_id ~= current_request_id then
        return
      end

      -- Check if buffer is still valid after async operation
      if not vim.api.nvim_buf_is_valid(buf) then
        callback(nil, nil)
        return
      end

      if not content or content == "" then
        callback(nil, nil)
        return
      end

      -- Append diagnostic section if there are diagnostics on this line
      local diag_section = get_diagnostic_section(buf, cursor_line)
      if diag_section then
        content = content .. diag_section
      end

      -- Return content via LSP callback - let Neovim handle display
      callback(nil, {
        contents = {
          kind = "markdown",
          value = content,
        },
      })
    end)
  end)
end

return M
