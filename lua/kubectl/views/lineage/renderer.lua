local hl = require("kubectl.actions.highlight")

local M = {}

--- Helper to safely get a value that might be vim.NIL
local function safe_value(val, default)
  if val == nil or val == vim.NIL then
    return default
  end
  return val
end

-- ---------------------------------------------------------------------------
-- RenderContext: builder that eliminates manual mark arithmetic
-- ---------------------------------------------------------------------------
local RenderContext = {}
RenderContext.__index = RenderContext

function RenderContext.new()
  return setmetatable({
    lines = {},
    marks = {},
    line_nodes = {},
    header_data = {},
    header_marks = {},
  }, RenderContext)
end

--- Add a plain text line. Returns self for chaining.
function RenderContext:line(text)
  table.insert(self.lines, text)
  return self
end

--- Add an empty line.
function RenderContext:blank()
  table.insert(self.lines, "")
  return self
end

--- Add a highlight mark on the *current* (last) line.
--- @param start_col number 0-indexed start column
--- @param end_col number 0-indexed end column (exclusive)
--- @param hl_group string highlight group
function RenderContext:mark(start_col, end_col, hl_group)
  table.insert(self.marks, {
    row = #self.lines - 1, -- 0-indexed row of last inserted line
    start_col = start_col,
    end_col = end_col,
    hl_group = hl_group,
  })
  return self
end

--- Map the current (last) line to a graph node.
function RenderContext:set_node(node)
  self.line_nodes[#self.lines] = node
  return self
end

--- Add a header line with optional mark.
function RenderContext:header(text, hl_group)
  table.insert(self.header_data, text)
  if hl_group then
    table.insert(self.header_marks, {
      row = #self.header_data - 1,
      start_col = 0,
      end_col = #text,
      hl_group = hl_group,
    })
  end
  return self
end

--- Emit a resource line: "[indent]Kind: namespace/name" with proper marks.
--- @param node table Graph node with kind, ns, name, key fields
--- @param opts table { indent = string, selected_key = string|nil }
function RenderContext:resource_line(node, opts)
  local indent = (opts and opts.indent) or ""
  local selected_key = opts and opts.selected_key
  local prefix = (opts and opts.prefix) or ""

  local kind = node.kind
  local ns = safe_value(node.ns, "cluster")
  local name = node.name
  local line = indent .. prefix .. kind .. ": " .. ns .. "/" .. name

  local is_selected = selected_key and (node.key == selected_key)
  local text_hl = is_selected and hl.symbols.success_bold or hl.symbols.white

  local offset = #indent + #prefix
  local kind_len = #kind
  local ns_len = #ns

  self:line(line)
  -- Kind
  self:mark(offset, offset + kind_len, text_hl)
  -- ": namespace/"
  self:mark(offset + kind_len, offset + kind_len + 2 + ns_len + 1, hl.symbols.gray)
  -- name
  self:mark(offset + kind_len + 2 + ns_len + 1, #line, text_hl)
  self:set_node(node)
  return self
end

--- Emit a kind header: "Kind (count)" with kind in white and count in gray.
function RenderContext:kind_header(kind, count)
  local header = kind .. " (" .. count .. ")"
  self:line(header)
  self:mark(0, #kind, hl.symbols.white)
  self:mark(#kind, #header, hl.symbols.gray)
  return self
end

--- Return the final result table.
function RenderContext:get()
  return {
    lines = self.lines,
    marks = self.marks,
    line_nodes = self.line_nodes,
    header_data = self.header_data,
    header_marks = self.header_marks,
  }
end

M.RenderContext = RenderContext

-- ---------------------------------------------------------------------------
-- Display mode: loading / building status
-- ---------------------------------------------------------------------------

--- Render loading or building status messages.
function M.render_status(ctx, phase, progress)
  if phase == "loading" then
    local processed, total = progress[1], progress[2]
    local percentage = total > 0 and math.floor((processed / total) * 100) or 0
    ctx:line("Loading lineage data...")
    ctx:blank()
    ctx:line(string.format("Progress: %d/%d (%d%%)", processed, total, percentage))
    ctx:blank()
    ctx:line("Please wait while resources are being fetched...")
  elseif phase == "building" then
    ctx:line("Building lineage graph...")
    ctx:blank()
    ctx:line("Analyzing resource relationships...")
  elseif phase == "empty" then
    ctx:line("No graph available. Press r to refresh.")
  end
end

--- Render an error state message.
function M.render_error(ctx, error_msg)
  ctx:line("Error: " .. (error_msg or "Failed to build lineage graph"))
  ctx:mark(0, 6, hl.symbols.error)
  ctx:blank()
  ctx:line("Press gr to retry.")
end

-- ---------------------------------------------------------------------------
-- Display mode: header
-- ---------------------------------------------------------------------------

--- Render the cache timestamp and filter status header.
function M.render_header(ctx, cache_timestamp, is_loading, orphan_filter)
  local filter_status = orphan_filter and " [Orphans Only]" or ""
  if cache_timestamp and not is_loading then
    local time = os.date("%H:%M:%S", cache_timestamp)
    local line = "Associated Resources - Cache refreshed at: " .. time .. filter_status
    ctx:header(line, hl.symbols.gray)
  else
    ctx:header("Associated Resources" .. filter_status)
  end
end

-- ---------------------------------------------------------------------------
-- Display mode: orphan view
-- ---------------------------------------------------------------------------

--- Build a lookup table from graph.nodes → key → node.
local function build_node_lookup(graph)
  local lookup = {}
  for i = 1, #graph.nodes do
    local node = graph.nodes[i]
    lookup[node.key] = node
  end
  return lookup
end

--- Render orphan resources grouped by kind.
function M.render_orphans(ctx, graph)
  -- Collect orphans grouped by kind
  local orphans_by_kind = {}
  for i = 1, #graph.nodes do
    local node = graph.nodes[i]
    if node.is_orphan and node.key ~= graph.root_key then
      local kind = node.kind or "Unknown"
      if not orphans_by_kind[kind] then
        orphans_by_kind[kind] = {}
      end
      table.insert(orphans_by_kind[kind], node)
    end
  end

  -- Sort kinds
  local sorted_kinds = {}
  for kind in pairs(orphans_by_kind) do
    table.insert(sorted_kinds, kind)
  end
  table.sort(sorted_kinds)

  if #sorted_kinds == 0 then
    ctx:line("No orphan resources found.")
    return
  end

  -- Warning
  local warning = "Note: Orphan detection is not 100% accurate. Verify before deleting."
  ctx:line(warning)
  ctx:mark(0, #warning, hl.symbols.warning)
  ctx:blank()

  local indent = "    "
  local branch = "\226\148\156\226\148\128 "
  local last_branch = "\226\148\148\226\148\128 "

  for kind_idx, kind in ipairs(sorted_kinds) do
    local nodes = orphans_by_kind[kind]

    -- Sort by ns/name
    table.sort(nodes, function(a, b)
      local a_ns = safe_value(a.ns, "cluster")
      local b_ns = safe_value(b.ns, "cluster")
      if a_ns ~= b_ns then
        return a_ns < b_ns
      end
      return a.name < b.name
    end)

    if kind_idx > 1 then
      ctx:blank()
    end

    ctx:kind_header(kind, #nodes)

    for i, node in ipairs(nodes) do
      local is_last = (i == #nodes)
      local tree_char = is_last and last_branch or branch
      local ns = safe_value(node.ns, "cluster")
      local line = indent .. tree_char .. ns .. "/" .. node.name

      local indent_len = #indent
      local tree_len = #tree_char
      local ns_len = #ns

      ctx:line(line)
      -- Tree branch + indent (gray)
      ctx:mark(0, indent_len + tree_len, hl.symbols.gray)
      -- Namespace/ (gray)
      ctx:mark(indent_len + tree_len, indent_len + tree_len + ns_len + 1, hl.symbols.gray)
      -- Name (white)
      ctx:mark(indent_len + tree_len + ns_len + 1, #line, hl.symbols.white)
      ctx:set_node(node)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Display mode: ownership tree + references
-- ---------------------------------------------------------------------------

--- Render the ownership tree for the selected resource plus reference nodes.
function M.render_tree(ctx, graph, selected_key)
  local node_lookup = build_node_lookup(graph)

  -- Get related nodes from Rust
  local related_keys_table = graph.get_related_nodes(selected_key)

  local related_keys_lookup = {}
  for i = 1, #related_keys_table do
    related_keys_lookup[related_keys_table[i]] = true
  end

  -- Find root ancestor of selected node
  local selected_node = node_lookup[selected_key]
  if not selected_node then
    return
  end

  local root_node = selected_node
  while root_node and root_node.parent_key and root_node.parent_key ~= vim.NIL do
    local parent = node_lookup[root_node.parent_key]
    if not parent then
      break
    end
    root_node = parent
  end

  local displayed_in_tree = {}

  local function build_tree(node, indent, visited)
    indent = indent or ""
    visited = visited or {}

    if visited[node.key] then
      return
    end
    visited[node.key] = true

    -- Skip root (cluster) node — process its children directly
    if node.key == graph.root_key then
      for i = 1, #node.children_keys do
        local child_key = node.children_keys[i]
        if related_keys_lookup[child_key] then
          local child = node_lookup[child_key]
          if child then
            build_tree(child, indent, visited)
          end
        end
      end
      return
    end

    ctx:resource_line(node, { indent = indent, selected_key = selected_key })
    displayed_in_tree[node.key] = true

    -- Recurse into owned children
    for i = 1, #node.children_keys do
      local child_key = node.children_keys[i]
      if related_keys_lookup[child_key] and not visited[child_key] then
        local child = node_lookup[child_key]
        if child then
          build_tree(child, indent .. "    ", visited)
        end
      end
    end
  end

  if root_node then
    build_tree(root_node, "", {})
  end

  -- Reference-only related nodes (not in ownership tree)
  for i = 1, #related_keys_table do
    local key = related_keys_table[i]
    if not displayed_in_tree[key] then
      local node = node_lookup[key]
      if node and node.key ~= graph.root_key then
        ctx:resource_line(node, { selected_key = selected_key })
        displayed_in_tree[key] = true
      end
    end
  end
end

return M
