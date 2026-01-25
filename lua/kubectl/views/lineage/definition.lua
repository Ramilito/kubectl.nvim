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

function M.processRow(rows, cached_api_resources, relationships)
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
      local owners = {}
      local relations = {}

      for _, relation in ipairs(relationships.getRelationship(item.kind, item, rows)) do
        if relation.relationship_type == "owner" then
          table.insert(owners, relation)
        elseif relation.relationship_type == "dependency" then
          table.insert(relations, relation)
        end
      end

      -- Add ownerReferences
      if item.metadata.ownerReferences then
        for _, owner in ipairs(item.metadata.ownerReferences) do
          -- TODO: Check if resource is NamespaceScoped or ClusterScoped in a better way
          local get_ns = function()
            if owner.kind == "Node" then
              return nil
            end
            return owner.namespace or item.metadata.namespace
          end
          table.insert(owners, {
            kind = owner.kind,
            apiVersion = owner.apiVersion,
            name = owner.name,
            uid = owner.uid,
            ns = get_ns(),
          })
        end
      end

      -- Build the row data
      row = {
        name = item.metadata.name,
        ns = item.metadata.namespace,
        apiVersion = rows.apiVersion,
        labels = item.metadata.labels,
        owners = owners,
        relations = relations,
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
        table.insert(resources, resource)
      end
    end
  end
  return resources
end

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

  -- Find the root ancestor of the selected node
  local selected_node = node_lookup[selected_node_key]
  if not selected_node then
    return lines, marks
  end

  local root_node = selected_node
  while root_node and root_node.parent_key do
    root_node = node_lookup[root_node.parent_key]
    if not root_node then
      break
    end
  end

  local function build_lines(node, indent)
    indent = indent or ""

    -- Skip the root node (cluster)
    if node.key == graph.root_key then
      -- Still need to display the children of the root node, so recurse over them
      for i = 1, #node.children_keys do
        local child_key = node.children_keys[i]
        if related_keys_lookup[child_key] then
          local child = node_lookup[child_key]
          if child then
            build_lines(child, indent) -- No indentation change for root's children
          end
        end
      end
      return
    end

    local key_values = {
      node.kind,
      node.ns or "cluster",
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
      -- Insert the line into the output
      table.insert(lines, line)
    end

    -- Recursively process the children if they are in the related nodes list
    for i = 1, #node.children_keys do
      local child_key = node.children_keys[i]
      if related_keys_lookup[child_key] then
        local child = node_lookup[child_key]
        if child then
          build_lines(child, indent .. "    ") -- Add indentation for children
        end
      end
    end
  end

  -- Start the traversal from the root ancestor
  if root_node then
    build_lines(root_node, "")
  else
    print("Error: Root node not found.")
  end

  return lines, marks
end

return M
