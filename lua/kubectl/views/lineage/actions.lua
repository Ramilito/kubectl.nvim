local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")

local M = {}

--- Helper: insert a mark entry into the marks table.
local function add_mark(marks, lines, start_col, end_col, hl_group)
  table.insert(marks, { row = #lines, start_col = start_col, end_col = end_col, hl_group = hl_group })
end

--- Navigate to the resource view for the given kind/ns/name.
function M.go_to_resource(kind, ns, name)
  local definition = require("kubectl.views.lineage.definition")
  local state = require("kubectl.state")
  local view = require("kubectl.views")

  vim.api.nvim_set_option_value("modified", false, { buf = 0 })
  vim.cmd.fclose()

  local view_name = definition.find_resource_name(kind) or kind

  state.filter_key = "metadata.name=" .. name
  if ns and ns ~= "cluster" then
    state.filter_key = state.filter_key .. ",metadata.namespace=" .. ns
  end
  view.resource_or_fallback(view_name)
end

--- Compute and display impact analysis for a node.
--- @param tree_id string The lineage tree id
--- @param resource_key string The resource key (kind/ns/name)
function M.impact_analysis(tree_id, resource_key)
  local client = require("kubectl.client")

  local ok, impact_json = pcall(client.compute_lineage_impact, tree_id, resource_key)
  if not ok then
    vim.notify("Failed to compute impact: " .. tostring(impact_json), vim.log.levels.ERROR)
    return
  end

  local impacted = vim.json.decode(impact_json)

  if not impacted or #impacted == 0 then
    vim.notify("No resources depend on " .. resource_key, vim.log.levels.INFO)
    return
  end

  local lines = {}
  local marks = {}

  -- Header
  local header = "Impact Analysis for: "
  add_mark(marks, lines, 0, #header, hl.symbols.header)
  add_mark(marks, lines, #header, #header + #resource_key, hl.symbols.info_bold)
  table.insert(lines, header .. resource_key)
  table.insert(lines, "")

  -- Subheader
  local subheader = "Resources that would be affected if deleted:"
  add_mark(marks, lines, 0, #subheader, hl.symbols.warning)
  table.insert(lines, subheader)
  table.insert(lines, "")

  -- Group by kind
  local by_kind = {}
  for _, item in ipairs(impacted) do
    local key = item[1]
    local edge_type = item[2]
    local kind = key:match("^([^/]+)/") or "Unknown"
    if not by_kind[kind] then
      by_kind[kind] = {}
    end
    table.insert(by_kind[kind], { key = key, edge_type = edge_type })
  end

  local sorted_kinds = {}
  for kind in pairs(by_kind) do
    table.insert(sorted_kinds, kind)
  end
  table.sort(sorted_kinds)

  local indent = "  "
  local bullet = "\226\128\162 "

  for kind_idx, kind in ipairs(sorted_kinds) do
    local items = by_kind[kind]

    if kind_idx > 1 then
      table.insert(lines, "")
    end

    -- Kind header with count
    local kind_header = kind .. " (" .. #items .. ")"
    add_mark(marks, lines, 0, #kind, hl.symbols.white)
    add_mark(marks, lines, #kind, #kind_header, hl.symbols.gray)
    table.insert(lines, kind_header)

    for _, item in ipairs(items) do
      local key = item.key
      local edge_type = item.edge_type

      local namespace, name = key:match("^[^/]+/([^/]+)/(.+)$")
      if not namespace then
        name = key:match("^[^/]+/(.+)$") or key
        namespace = nil
      end

      local resource_part = namespace and (namespace .. "/" .. name) or name
      local relationship = edge_type == "owns" and "[owns]" or "[references]"
      local line = indent .. bullet .. resource_part .. " " .. relationship

      local indent_len = #indent
      local bullet_len = #bullet
      local resource_len = #resource_part

      -- Bullet (gray)
      local bp = indent_len + bullet_len
      add_mark(marks, lines, 0, bp, hl.symbols.gray)

      if namespace then
        add_mark(marks, lines, bp, bp + #namespace + 1, hl.symbols.gray)
        add_mark(marks, lines, bp + #namespace + 1, bp + resource_len, hl.symbols.white)
      else
        add_mark(marks, lines, bp, bp + resource_len, hl.symbols.white)
      end

      -- Relationship tag
      local rel_start = bp + resource_len + 1
      local rel_color = edge_type == "owns" and hl.symbols.error or hl.symbols.warning
      add_mark(marks, lines, rel_start, rel_start + #relationship, rel_color)

      table.insert(lines, line)
    end
  end

  table.insert(lines, "")

  -- Footer
  local total_text = "Total: "
  local count_text = tostring(#impacted)
  local suffix_text = #impacted == 1 and " resource would be impacted" or " resources would be impacted"
  add_mark(marks, lines, 0, #total_text, hl.symbols.header)
  add_mark(marks, lines, #total_text, #total_text + #count_text, hl.symbols.error_bold)
  local suffix_end = #total_text + #count_text + #suffix_text
  add_mark(marks, lines, #total_text + #count_text, suffix_end, hl.symbols.header)
  table.insert(lines, total_text .. count_text .. suffix_text)

  -- Create floating window using shared abstraction
  local height = math.min(#lines + 2, 30)
  local buf = buffers.floating_dynamic_buffer("k8s_lineage_impact", "Impact Analysis", nil, {
    enter = true,
    width = 80,
    height = height,
  })

  buffers.set_content(buf, {
    content = lines,
    marks = marks,
  })
end

--- Export lineage subgraph in the specified format.
--- @param tree_id string The lineage tree id
--- @param resource_key string The resource key (kind/ns/name)
--- @param format string "dot" or "mermaid"
function M.export(tree_id, resource_key, format)
  local client = require("kubectl.client")

  local export_fn, ext, ft
  if format == "dot" then
    export_fn = client.export_lineage_subgraph_dot
    ext = "dot"
    ft = "dot"
  elseif format == "mermaid" then
    export_fn = client.export_lineage_subgraph_mermaid
    ext = "mmd"
    ft = "mermaid"
  else
    vim.notify("Unknown export format: " .. format, vim.log.levels.ERROR)
    return
  end

  ---@diagnostic disable-next-line: undefined-field
  local ok_export, content = pcall(export_fn, tree_id, resource_key)
  if not ok_export then
    vim.notify("Failed to export " .. format .. ": " .. tostring(content), vim.log.levels.ERROR)
    return
  end

  vim.cmd("fclose!")
  vim.schedule(function()
    vim.cmd("vsplit")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_name(buf, "lineage_subgraph." .. ext)
    vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    local export_lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, export_lines)
  end)
end

return M
