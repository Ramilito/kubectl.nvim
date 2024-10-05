local M = {
  resource = "lineage",
  display_name = "Lineage",
  ft = "k8s_lineage",
}

-- Function to collect all resources from the data sample
function M.collect_all_resources(data_sample)
  local resources = {}
  for kind_key, resource_group in pairs(data_sample) do
    if resource_group.data then
      -- Extract resource instances from the 'data' field
      for _, resource in ipairs(resource_group.data) do
        resource.kind = resource.kind and resource.kind:lower()
          or resource_group.kind and resource_group.kind:lower()
          or kind_key:lower()
        table.insert(resources, resource)
      end
    end
  end
  return resources
end

-- Function to create a unique key for resources
function M.get_resource_key(resource)
  local ns_part = resource.ns or "cluster"
  local kind = resource.kind and resource.kind:lower() or "unknownkind"
  return kind .. "/" .. ns_part .. "/" .. resource.name
end

-- Function to build a graph of resources
function M.build_graph(resources)
  local graph = {}

  -- First pass: map keys to resources and initialize graph nodes
  for _, resource in ipairs(resources) do
    if resource.name then
      resource.kind = resource.kind and resource.kind:lower() or "unknownkind"
      local resource_key = M.get_resource_key(resource)
      graph[resource_key] = { resource = resource, neighbors = {} }
    end
  end

  -- Second pass: build ownership edges
  for _, resource in ipairs(resources) do
    if resource.name then
      local resource_key = M.get_resource_key(resource)
      local node = graph[resource_key]
      if resource.owners then
        for _, owner in ipairs(resource.owners) do
          owner.kind = owner.kind and owner.kind:lower() or "unknownkind"
          owner.ns = owner.ns or resource.ns -- Assume same namespace if not specified
          local owner_key = M.get_resource_key(owner)
          if not graph[owner_key] then
            graph[owner_key] = { resource = owner, neighbors = {} }
          end
          -- Add bidirectional edge
          table.insert(node.neighbors, graph[owner_key])
          table.insert(graph[owner_key].neighbors, node)
        end
      end
    end
  end

  -- Third pass: build label selector edges
  for _, resource in ipairs(resources) do
    if resource.name and resource.selectors then
      local resource_key = M.get_resource_key(resource)
      local node = graph[resource_key]

      -- Match resources by label selectors
      for _, potential_child in ipairs(resources) do
        if potential_child.labels then
          local is_match = true
          -- Check if labels match the selector
          for key, value in pairs(resource.selectors) do
            if potential_child.labels[key] ~= value then
              is_match = false
              break
            end
          end
          if is_match then
            local child_key = M.get_resource_key(potential_child)
            if not graph[child_key] then
              graph[child_key] = { resource = potential_child, neighbors = {} }
            end
            -- Add bidirectional edge (resource -> child and child -> resource)
            table.insert(node.neighbors, graph[child_key])
            table.insert(graph[child_key].neighbors, node)
          end
        end
      end
    end
  end

  return graph
end

-- Function to find associated resources using BFS traversal
function M.find_associated_resources(graph, start_key)
  local visited = {}
  local queue = {}
  local associated_resources = {}

  if not graph[start_key] then
    print("Selected resource not found in the graph.")
    return associated_resources
  end

  table.insert(queue, { key = start_key, level = 0 })
  visited[start_key] = true

  while #queue > 0 do
    local current = table.remove(queue, 1)
    local current_key = current.key
    local level = current.level
    local node = graph[current_key]

    if node then
      node.resource.level = level
      table.insert(associated_resources, node.resource)
      for _, neighbor in ipairs(node.neighbors) do
        local neighbor_key = M.get_resource_key(neighbor.resource)
        if not visited[neighbor_key] then
          visited[neighbor_key] = true
          table.insert(queue, { key = neighbor_key, level = level + 1 })
        end
      end
    end
  end

  return associated_resources
end

return M
