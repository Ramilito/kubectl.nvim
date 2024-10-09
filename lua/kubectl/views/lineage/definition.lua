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

-- Function to recursively build the dependency graph
function M.build_graph(data)
  local hierarchy = {}

  local function add_node(resource)
    local key = M.get_resource_key(resource)
    if not hierarchy[key] then
      hierarchy[key] = { children = {} }
    end
  end

  local function add_relationship(child, parent)
    if not hierarchy[parent] then
      hierarchy[parent] = { children = {} }
    end
    table.insert(hierarchy[parent].children, child)
  end

  -- Helper function to build hierarchy from owners recursively
  local function process_owners(child, owners)
    for _, owner in ipairs(owners) do
      local parent_key = M.get_resource_key(owner)
      local child_key = M.get_resource_key(child)

      -- Add parent and child to the hierarchy
      add_node(owner)
      add_relationship(child_key, parent_key)

      -- Recursively process owner if it has owners of its own
      if owner.owners then
        process_owners(owner, owner.owners)
      end
    end
  end

  -- Iterate through the data and create relationships
  for _, item in ipairs(data) do
    add_node(item)

    -- Process its owners if any
    if item.owners and #item.owners > 0 then
      process_owners(item, item.owners)
    end
  end

  return hierarchy
end

function M.get_relationships(graph, start_key)
  local result = {}
  local queue = {}
  local visited = {}

  -- Initialize the queue with the starting key and distance 0
  table.insert(queue, { key = start_key, distance = 0 })

  while #queue > 0 do
    -- Dequeue the next node
    local current = table.remove(queue, 1)
    local key = current.key
    local distance = current.distance

    if not visited[key] then
      visited[key] = true
      result[key] = distance

      local node = graph[key]
      if node and node.children then
        for _, child in ipairs(node.children) do
          if not visited[child] then
            -- Enqueue child nodes with incremented distance
            table.insert(queue, { key = child, distance = distance + 1 })
          end
        end
      end
    end
  end

  return result
end

return M
