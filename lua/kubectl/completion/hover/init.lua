local commands = require("kubectl.actions.commands")
local formatters = require("kubectl.completion.hover.formatters")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

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
  local is_cluster_scoped = not vim.tbl_contains(def.headers or {}, "NAMESPACE")
  local name_col = is_cluster_scoped and 1 or 2
  local ns_col = is_cluster_scoped and nil or 1

  -- Check if cursor is on content row
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = state.get_buffer_state(bufnr)
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

  -- Fetch resource data asynchronously
  commands.run_async("get_single_async", {
    gvk = gvk,
    namespace = ns,
    name = name,
    output = "Json",
  }, function(data)
    vim.schedule(function()
      if not data then
        callback(nil, nil)
        return
      end

      local ok, decoded = pcall(vim.json.decode, data)
      if not ok or not decoded then
        callback(nil, nil)
        return
      end

      local content = formatters.format(decoded, gvk.k)
      local lines = vim.split(content, "\n")

      -- Open floating preview with custom close events (no BufLeave/buffer changes)
      vim.lsp.util.open_floating_preview(lines, "markdown", {
        border = "rounded",
        close_events = { "CursorMoved", "InsertEnter" },
      })

      -- Return nil to prevent default handler from opening another window
      callback(nil, nil)
    end)
  end)
end

return M
