local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local renderer = require("kubectl.views.lineage.renderer")

local M = {}

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

--- Group impacted resources by kind, sorted alphabetically.
--- @param impacted table Array of {key, edge_type} tuples
--- @return table sorted_kinds, table by_kind
local function group_by_kind(impacted)
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

  return sorted_kinds, by_kind
end

--- Render impact analysis content into a RenderContext.
--- @param ctx table RenderContext instance
--- @param resource_key string
--- @param impacted table
local function render_impact(ctx, resource_key, impacted)
  -- Header
  local header = "Impact Analysis for: "
  ctx:line(header .. resource_key)
  ctx:mark(0, #header, hl.symbols.header)
  ctx:mark(#header, #header + #resource_key, hl.symbols.info_bold)
  ctx:blank()

  -- Subheader
  local subheader = "Resources that would be affected if deleted:"
  ctx:line(subheader)
  ctx:mark(0, #subheader, hl.symbols.warning)
  ctx:blank()

  -- Grouped resources
  local sorted_kinds, by_kind = group_by_kind(impacted)

  local indent = "  "
  local bullet = "\226\128\162 "

  for kind_idx, kind in ipairs(sorted_kinds) do
    local items = by_kind[kind]

    if kind_idx > 1 then
      ctx:blank()
    end

    ctx:kind_header(kind, #items)

    for _, item in ipairs(items) do
      local namespace, name = item.key:match("^[^/]+/([^/]+)/(.+)$")
      if not namespace then
        name = item.key:match("^[^/]+/(.+)$") or item.key
        namespace = nil
      end

      local resource_part = namespace and (namespace .. "/" .. name) or name
      local tag = item.edge_type == "owns" and "[owns]" or "[references]"
      local line = indent .. bullet .. resource_part .. " " .. tag

      local bp = #indent + #bullet

      ctx:line(line)
      ctx:mark(0, bp, hl.symbols.gray)

      if namespace then
        ctx:mark(bp, bp + #namespace + 1, hl.symbols.gray)
        ctx:mark(bp + #namespace + 1, bp + #resource_part, hl.symbols.white)
      else
        ctx:mark(bp, bp + #resource_part, hl.symbols.white)
      end

      local tag_start = bp + #resource_part + 1
      local tag_hl = item.edge_type == "owns" and hl.symbols.error or hl.symbols.warning
      ctx:mark(tag_start, tag_start + #tag, tag_hl)
    end
  end

  ctx:blank()

  -- Footer
  local total_text = "Total: "
  local count_text = tostring(#impacted)
  local suffix = #impacted == 1 and " resource would be impacted" or " resources would be impacted"
  ctx:line(total_text .. count_text .. suffix)
  ctx:mark(0, #total_text, hl.symbols.header)
  ctx:mark(#total_text, #total_text + #count_text, hl.symbols.error_bold)
  ctx:mark(#total_text + #count_text, #total_text + #count_text + #suffix, hl.symbols.header)
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

  local ctx = renderer.RenderContext.new()
  render_impact(ctx, resource_key, impacted)

  local result = ctx:get()
  local height = math.min(#result.lines + 2, 30)
  local buf = buffers.floating_dynamic_buffer(
    "k8s_lineage_impact",
    "Impact Analysis",
    nil,
    { enter = true, width = 80, height = height }
  )

  buffers.set_content(buf, {
    content = result.lines,
    marks = result.marks,
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
