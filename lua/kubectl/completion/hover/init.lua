local commands = require("kubectl.actions.commands")
local formatters = require("kubectl.completion.hover.formatters")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

-- Track current hover window
local hover_win = nil
local hover_buf = nil

--- Close hover window if open
local function close_hover()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_win_close(hover_win, true)
  end
  hover_win = nil
  hover_buf = nil
end

--- Open floating window with markdown content
---@param content string Markdown content
local function open_hover_window(content)
  close_hover()

  local lines = vim.split(content, "\n")

  -- Calculate dimensions
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, #line)
  end
  local width = math.min(max_width + 2, math.floor(vim.o.columns * 0.6))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.4))

  -- Create buffer
  hover_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(hover_buf, 0, -1, false, lines)
  vim.bo[hover_buf].filetype = "markdown"
  vim.bo[hover_buf].modifiable = false

  -- Create window
  hover_win = vim.api.nvim_open_win(hover_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })

  -- Set window options
  vim.wo[hover_win].wrap = true
  vim.wo[hover_win].conceallevel = 2
  vim.wo[hover_win].concealcursor = "n"

  -- Close on Esc or q
  vim.keymap.set("n", "<Esc>", close_hover, { buffer = hover_buf, nowait = true })
  vim.keymap.set("n", "q", close_hover, { buffer = hover_buf, nowait = true })
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

--- Show hover for current resource (direct call, not via LSP)
function M.show()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local resource = resource_from_filetype(ft)

  if not resource then
    return
  end

  local builder = manager.get(resource)
  if not builder or not builder.definition then
    return
  end

  local name, ns = get_selection(builder)
  if not name then
    return
  end

  local gvk = builder.definition.gvk
  if not gvk then
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
        return
      end

      local ok, decoded = pcall(vim.json.decode, data)
      if not ok or not decoded then
        return
      end

      local content = formatters.format(decoded, gvk.k)
      open_hover_window(content)
    end)
  end)
end

--- Handle hover request (LSP callback version)
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
      -- Use our custom hover window instead of LSP's
      open_hover_window(content)
      -- Still call callback with nil to prevent LSP from opening its own window
      callback(nil, nil)
    end)
  end)
end

return M
