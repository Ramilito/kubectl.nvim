local M = {
  resource = "lineage",
  display_name = "Lineage",
  ft = "k8s_lineage",
}

local function get_kind(resource, default_kind)
  return (resource.kind and resource.kind:lower()) or (default_kind and default_kind:lower()) or "unknownkind"
end

function M.collect_all_resources(data_sample)
  local resources = {}
  for kind_key, resource_group in pairs(data_sample) do
    if resource_group.data then
      for _, resource in ipairs(resource_group.data) do
        resource.kind = get_kind(resource, resource_group.kind or kind_key)
        table.insert(resources, resource)
      end
    end
  end
  return resources
end

function M.get_resource_key(resource)
  local ns = resource.ns or "cluster"
  local kind = get_kind(resource)
  return string.format("%s/%s/%s", kind, ns, resource.name)
end

local function init_graph_node(graph, resource)
  local key = M.get_resource_key(resource)
  if not graph[key] then
    graph[key] = { resource = resource, neighbors = {} }
  end
  return graph[key]
end

local function add_bidirectional_edge(node, neighbor)
  table.insert(node.neighbors, neighbor)
  table.insert(neighbor.neighbors, node)
end

function M.build_graph(resources)
  local graph = {}

  -- First pass: initialize graph nodes
  for _, resource in ipairs(resources) do
    if resource.name then
      init_graph_node(graph, resource)
    end
  end

  -- Second pass: build ownership edges
  for _, resource in ipairs(resources) do
    if resource.owners then
      local node = init_graph_node(graph, resource)
      for _, owner in ipairs(resource.owners) do
        owner.kind = get_kind(owner)
        owner.ns = owner.ns or resource.ns
        local owner_node = init_graph_node(graph, owner)
        add_bidirectional_edge(node, owner_node)
      end
    end
  end

  -- Third pass: build label selector edges
  for _, resource in ipairs(resources) do
    if resource.selectors then
      local node = init_graph_node(graph, resource)
      for _, potential_child in ipairs(resources) do
        local match = true
        if potential_child.labels then
          for key, value in pairs(resource.selectors) do
            if potential_child.labels[key] ~= value then
              match = false
              break
            end
          end
          if match then
            local child_node = init_graph_node(graph, potential_child)
            add_bidirectional_edge(node, child_node)
          end
        end
      end
    end
  end

  return graph
end

-- Function to find associated resources using BFS traversal
function M.find_associated_resources(graph, start_key)
  local visited, queue, associated_resources = {}, {}, {}

  if not graph[start_key] then
    print("Selected resource not found in the graph.")
    return associated_resources
  end

  table.insert(queue, { key = start_key, level = 0 })
  visited[start_key] = true

  while #queue > 0 do
    local current = table.remove(queue, 1)
    local node = graph[current.key]

    if node then
      node.resource.level = current.level
      table.insert(associated_resources, node.resource)
      for _, neighbor in ipairs(node.neighbors) do
        local neighbor_key = M.get_resource_key(neighbor.resource)
        if not visited[neighbor_key] then
          visited[neighbor_key] = true
          table.insert(queue, { key = neighbor_key, level = current.level + 1 })
        end
      end
    end
  end

  return associated_resources
end

return M
