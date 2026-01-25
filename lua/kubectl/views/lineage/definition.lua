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
    if not item.kind then
      return
    end

    item.metadata.managedFields = {}

    local cache_key = nil
    for _, value in pairs(cached_api_resources.values) do
      if value.api_version and item.api_version then
        if string.lower(value.api_version) == string.lower(item.api_version) and value.gvk.k == item.kind then
          cache_key = value.crd_name
        end
      end
    end

    local row

    if item.metadata.name then
      -- Build the row data - relationships will be extracted in Rust
      row = {
        kind = item.kind,
        name = item.metadata.name,
        ns = item.metadata.namespace,
        apiVersion = item.apiVersion or rows.apiVersion,
        labels = item.metadata.labels,
        metadata = item.metadata,
        spec = item.spec,
      }

      -- Add selectors if available
      if item.spec and item.spec.selector then
        local label_selector = item.spec.selector.matchLabels or item.spec.selector
        if label_selector then
          row.selectors = label_selector
        end
      end

      -- Add the row to the cache if cache_key is available
      if cache_key then
        if not cached_api_resources.values[cache_key].data then
          cached_api_resources.values[cache_key].data = {}
        end
        table.insert(cached_api_resources.values[cache_key].data, row)
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

function M.build_display_lines(graph, selected_node_key)
  local lines = {}
  local marks = {}

  -- Get related node keys from Rust
  local related_keys_table = graph.get_related_nodes(selected_node_key)

  -- Convert to Lua table and create lookup
  local related_keys_lookup = {}
  for i = 1, #related_keys_table do
    related_keys_lookup[related_keys_table[i]] = true
  end

  -- Create node lookup from graph.nodes
  local node_lookup = {}
  for i = 1, #graph.nodes do
    local node = graph.nodes[i]
    node_lookup[node.key] = node
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

    -- Build the line to display
    local line = indent .. key_values[1] .. ": " .. key_values[2] .. "/" .. key_values[3]

    -- Determine highlight group based on whether the node is selected
    local hlgroup = node.key == selected_node_key and hl.symbols.success_bold or hl.symbols.white_bold

    -- Insert marks for highlighting
    if line then
      table.insert(marks, {
        row = #lines,
        start_col = #indent + #key_values[1] + #key_values[2] + 3,
        end_col = #line,
        hl_group = hlgroup,
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

    -- Show leaf relationships as flat references (with arrow prefix, no recursion)
    for i = 1, #node.leaf_keys do
      local leaf_key = node.leaf_keys[i]
      if related_keys_lookup[leaf_key] and not displayed_in_tree[leaf_key] then
        local leaf = node_lookup[leaf_key]
        if leaf then
          local leaf_values = {
            leaf.kind,
            safe_value(leaf.ns, "cluster"),
            leaf.name,
          }
          local leaf_line = indent .. "    → " .. leaf_values[1] .. ": " .. leaf_values[2] .. "/" .. leaf_values[3]
          table.insert(marks, {
            row = #lines,
            start_col = #indent + 6 + #leaf_values[1] + #leaf_values[2] + 3,
            end_col = #leaf_line,
            hl_group = hl.symbols.pending,
          })
          table.insert(lines, leaf_line)
          displayed_in_tree[leaf_key] = true
        end
      end
    end
  end

  -- Start the traversal from the root ancestor
  if root_node then
    build_tree_lines(root_node, "", {})
  end

  return lines, marks
end

return M
