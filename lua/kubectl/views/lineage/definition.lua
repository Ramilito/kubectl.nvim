local client = require("kubectl.client")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local M = {
  resource = "lineage",
  display_name = "Lineage",
  ft = "k8s_lineage",
}

local function get_kind(resource, default_kind)
  return (resource.kind and resource.kind) or (default_kind and default_kind) or "unknownkind"
end

--- Helper to safely get a value that might be vim.NIL
local function safe_value(val, default)
  if val == nil or val == vim.NIL then
    return default
  end
  return val
end

function M.processRow(rows, cached_api_resources)
  if not rows or type(rows) == "string" then
    return
  end
  if type(rows) ~= "table" then
    return
  end
  for _, item in ipairs(rows) do
    -- Skip invalid items instead of returning (which would skip all remaining items)
    if item.kind and item.metadata and item.metadata.name then
      -- Clear managedFields to reduce payload size
      item.metadata.managedFields = nil

      -- Find cache key for this resource
      local cache_key = nil
      for _, value in pairs(cached_api_resources.values) do
        if value.api_version and item.apiVersion then
          if string.lower(value.api_version) == string.lower(item.apiVersion) and value.gvk.k == item.kind then
            cache_key = value.crd_name
          end
        end
      end

      -- Add the raw item to the cache - Rust will extract all needed fields
      if cache_key then
        if not cached_api_resources.values[cache_key].data then
          cached_api_resources.values[cache_key].data = {}
        end
        table.insert(cached_api_resources.values[cache_key].data, item)
      end
    end
  end
end

function M.collect_all_resources(data_sample)
  local resources = {}
  for kind_key, resource_group in pairs(data_sample) do
    if resource_group.data then
      for _, resource in ipairs(resource_group.data) do
        resource.kind = get_kind(resource, resource_group.gvk.k or kind_key)
        -- Add namespaced flag from API resource metadata
        resource.namespaced = resource_group.namespaced
        table.insert(resources, resource)
      end
    end
  end
  return resources
end

--- Build lineage graph asynchronously in a worker thread
--- @param data table The collected resources
--- @param callback function Called with (graph) when done
function M.build_graph_async(data, callback)
  local commands = require("kubectl.actions.commands")
  local context = state.getContext()
  local root_name = context.clusters[1].name

  -- Call Rust backend in a worker thread via commands.run_async
  commands.run_async("build_lineage_graph_worker", {
    resources = data,
    root_name = root_name,
  }, function(result_json, err)
    if err then
      vim.schedule(function()
        vim.notify("Error building lineage graph: " .. tostring(err), vim.log.levels.ERROR)
        callback(nil)
      end)
      return
    end

    local ok, result = pcall(vim.json.decode, result_json)
    if not ok then
      vim.schedule(function()
        vim.notify("Error decoding lineage graph: " .. tostring(result), vim.log.levels.ERROR)
        callback(nil)
      end)
      return
    end

    -- Create a graph object compatible with the display code
    local graph = {
      nodes = result.nodes,
      root_key = result.root_key,
      tree_id = result.tree_id,
      -- Wrapper function that calls Rust to get related nodes
      get_related_nodes = function(node_key)
        local related_json = client.get_lineage_related_nodes(result.tree_id, node_key)
        return vim.json.decode(related_json)
      end,
    }

    vim.schedule(function()
      callback(graph)
    end)
  end)
end

--- Build lineage graph synchronously (for backward compatibility)
function M.build_graph(data)
  local context = state.getContext()
  local root_name = context.clusters[1].name

  -- Convert data to JSON string for Rust
  local resources_json = vim.json.encode(data)

  -- Call Rust backend to build the graph
  local graph = client.build_lineage_graph(resources_json, root_name)

  return graph
end

--- Get orphan resources from the lineage graph
--- @param graph table The lineage graph
--- @return table Lookup table of orphan keys
function M.get_orphans(graph)
  if not graph or not graph.nodes then
    return {}
  end

  local orphan_lookup = {}
  -- Collect orphans from node.is_orphan property
  for i = 1, #graph.nodes do
    local node = graph.nodes[i]
    if node.is_orphan then
      orphan_lookup[node.key] = true
    end
  end
  return orphan_lookup
end

--- Parse current line to extract resource key
--- @param line string The current line text
--- @return string|nil The resource key in format "kind/ns/name" or nil if parse fails
function M.parse_line_resource_key(line)
  -- Remove leading whitespace and orphan prefix
  local trimmed = line:gsub("^%s*", ""):gsub("^%[orphan%]%s*", "")

  -- Expected format: "Kind: namespace/name"
  local kind, rest = trimmed:match("^([^:]+):%s*(.+)$")
  if not kind or not rest then
    return nil
  end

  -- Split namespace/name
  local ns, name = rest:match("^([^/]+)/(.+)$")
  if not ns or not name then
    return nil
  end

  -- Trim whitespace
  kind = vim.trim(kind):lower()
  ns = vim.trim(ns):lower()
  name = vim.trim(name):lower()

  -- Build resource key
  if ns == "cluster" then
    -- Cluster-scoped resource
    return kind .. "/" .. name
  else
    -- Namespaced resource
    return kind .. "/" .. ns .. "/" .. name
  end
end

--- Display impact analysis results in a floating window
--- @param impacted table Array of {resource_key, edge_type} tuples
--- @param resource_key string The resource being analyzed
function M.display_impact_results(impacted, resource_key)
  if not impacted or #impacted == 0 then
    vim.notify("No resources depend on " .. resource_key, vim.log.levels.INFO)
    return
  end

  local lines = {
    "Impact Analysis for: " .. resource_key,
    "",
    "Resources that would be affected if deleted:",
    "",
  }

  for _, item in ipairs(impacted) do
    local key = item[1]
    local edge_type = item[2]
    local relationship = edge_type == "owns" and "owns (parent)" or "references"
    table.insert(lines, "  " .. key .. " [" .. relationship .. "]")
  end

  table.insert(lines, "")
  table.insert(lines, "Total: " .. #impacted .. " resources would be impacted")

  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "k8s_lineage_impact", { buf = buf })

  -- Calculate window size
  local width = 80
  local height = math.min(#lines + 2, 30)

  local opts = {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " Impact Analysis ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Close on q or Escape
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

function M.build_display_lines(graph, selected_node_key, orphan_filter_enabled)
  local lines = {}
  local marks = {}

  -- Create node lookup from graph.nodes
  local node_lookup = {}
  for i = 1, #graph.nodes do
    local node = graph.nodes[i]
    node_lookup[node.key] = node
  end

  -- When orphan filter is enabled, show ONLY orphans (ignore selected resource)
  if orphan_filter_enabled then
    local orphan_lookup = M.get_orphans(graph)

    -- Sort orphan keys for consistent display
    local orphan_keys = {}
    for key, _ in pairs(orphan_lookup) do
      table.insert(orphan_keys, key)
    end
    table.sort(orphan_keys)

    if #orphan_keys == 0 then
      table.insert(lines, "No orphan resources found.")
      return lines, marks
    end

    for _, key in ipairs(orphan_keys) do
      local node = node_lookup[key]
      if node and node.key ~= graph.root_key then
        local key_values = {
          node.kind,
          safe_value(node.ns, "cluster"),
          node.name,
        }

        local line = key_values[1] .. ": " .. key_values[2] .. "/" .. key_values[3]
        local kind_len = #key_values[1]
        local ns_len = #key_values[2]

        -- Kind (white)
        table.insert(marks, {
          row = #lines,
          start_col = 0,
          end_col = kind_len,
          hl_group = hl.symbols.white,
        })

        -- ": namespace/" (gray)
        table.insert(marks, {
          row = #lines,
          start_col = kind_len,
          end_col = kind_len + 2 + ns_len + 1,
          hl_group = hl.symbols.gray,
        })

        -- Resource name (white)
        table.insert(marks, {
          row = #lines,
          start_col = kind_len + 2 + ns_len + 1,
          end_col = #line,
          hl_group = hl.symbols.white,
        })

        table.insert(lines, line)
      end
    end

    return lines, marks
  end

  -- Normal mode: show relationships of selected resource
  -- Get related node keys from Rust
  local related_keys_table = graph.get_related_nodes(selected_node_key)

  -- Convert to Lua table and create lookup
  local related_keys_lookup = {}
  for i = 1, #related_keys_table do
    related_keys_lookup[related_keys_table[i]] = true
  end

  -- Find the root ancestor of the selected node (following ownership chain)
  local selected_node = node_lookup[selected_node_key]
  if not selected_node then
    return lines, marks
  end

  local root_node = selected_node
  -- Traverse up to find the root (parent_key can be nil or vim.NIL)
  while root_node and root_node.parent_key and root_node.parent_key ~= vim.NIL do
    local parent = node_lookup[root_node.parent_key]
    if not parent then
      break
    end
    root_node = parent
  end

  -- Track which nodes are displayed in the ownership tree
  local displayed_in_tree = {}

  local function build_tree_lines(node, indent, visited)
    indent = indent or ""
    visited = visited or {}

    -- Prevent infinite loops
    if visited[node.key] then
      return
    end
    visited[node.key] = true

    -- Skip the root node (cluster)
    if node.key == graph.root_key then
      -- Process children of root (top-level owned resources)
      for i = 1, #node.children_keys do
        local child_key = node.children_keys[i]
        if related_keys_lookup[child_key] then
          local child = node_lookup[child_key]
          if child then
            build_tree_lines(child, indent, visited)
          end
        end
      end
      return
    end

    local key_values = {
      node.kind,
      safe_value(node.ns, "cluster"),
      node.name,
    }

    local line = indent .. key_values[1] .. ": " .. key_values[2] .. "/" .. key_values[3]

    local is_selected = node.key == selected_node_key
    local text_hl = is_selected and hl.symbols.success_bold or hl.symbols.white

    if line then
      local indent_len = #indent
      local kind_len = #key_values[1]
      local ns_len = #key_values[2]

      -- Kind (highlighted)
      table.insert(marks, {
        row = #lines,
        start_col = indent_len,
        end_col = indent_len + kind_len,
        hl_group = text_hl,
      })

      -- ": namespace/" (gray)
      table.insert(marks, {
        row = #lines,
        start_col = indent_len + kind_len,
        end_col = indent_len + kind_len + 2 + ns_len + 1,
        hl_group = hl.symbols.gray,
      })

      -- Resource name (highlighted)
      table.insert(marks, {
        row = #lines,
        start_col = indent_len + kind_len + 2 + ns_len + 1,
        end_col = #line,
        hl_group = text_hl,
      })

      table.insert(lines, line)
      displayed_in_tree[node.key] = true
    end

    -- Process ONLY children (ownership hierarchy via ownerReferences)
    for i = 1, #node.children_keys do
      local child_key = node.children_keys[i]
      if related_keys_lookup[child_key] and not visited[child_key] then
        local child = node_lookup[child_key]
        if child then
          build_tree_lines(child, indent .. "    ", visited)
        end
      end
    end

    -- Note: leaf_keys (reference relationships) are NOT displayed as children here
    -- They will be displayed at root level after the ownership tree is built
  end

  -- Start the traversal from the root ancestor
  if root_node then
    build_tree_lines(root_node, "", {})
  end

  -- Display any related resources that weren't shown via ownership hierarchy
  -- These are resources connected only via references (selectors, etc.)
  for i = 1, #related_keys_table do
    local key = related_keys_table[i]
    if not displayed_in_tree[key] then
      local node = node_lookup[key]
      if node and node.key ~= graph.root_key then
        local key_values = {
          node.kind,
          safe_value(node.ns, "cluster"),
          node.name,
        }
        local line = key_values[1] .. ": " .. key_values[2] .. "/" .. key_values[3]

        local is_selected = node.key == selected_node_key
        local text_hl = is_selected and hl.symbols.success_bold or hl.symbols.white

        local kind_len = #key_values[1]
        local ns_len = #key_values[2]

        -- Kind (highlighted)
        table.insert(marks, {
          row = #lines,
          start_col = 0,
          end_col = kind_len,
          hl_group = text_hl,
        })

        -- ": namespace/" (gray)
        table.insert(marks, {
          row = #lines,
          start_col = kind_len,
          end_col = kind_len + 2 + ns_len + 1,
          hl_group = hl.symbols.gray,
        })

        -- Resource name (highlighted)
        table.insert(marks, {
          row = #lines,
          start_col = kind_len + 2 + ns_len + 1,
          end_col = #line,
          hl_group = text_hl,
        })

        table.insert(lines, line)
        displayed_in_tree[key] = true
      end
    end
  end

  return lines, marks
end

return M
