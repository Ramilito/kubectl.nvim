local hl = require("kubectl.actions.highlight")
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

-- Function to build the parents mapping
local function build_parents_mapping(graph)
  local parents = {}
  for parent_key, node in pairs(graph) do
    if node.children then
      for _, child_key in ipairs(node.children) do
        parents[child_key] = parent_key
      end
    end
  end
  return parents
end

-- Function to get the path to root
local function get_path_to_root(parents, node_key)
  local path = {}
  local current = node_key
  while current do
    table.insert(path, 1, current) -- Insert at the beginning
    current = parents[current]
  end
  return path
end

local function build_tree(graph, current_node_key, distance, path_nodes, selected_node, visited)
  visited = visited or {}
  if visited[current_node_key] then
    return nil
  end
  visited[current_node_key] = true

  local subtree = { distance = distance }
  local node = graph[current_node_key]
  if node and node.children then
    subtree.children = {}
    for _, child_key in ipairs(node.children) do
      if current_node_key == selected_node or path_nodes[child_key] then
        local child_subtree = build_tree(graph, child_key, distance + 1, path_nodes, selected_node, visited)
        if child_subtree then
          subtree.children[child_key] = child_subtree
        end
      else
        -- Include siblings as nodes without their descendants
        subtree.children[child_key] = { distance = distance + 1 }
      end
    end
  end
  return subtree
end

function M.get_relationship(graph, key)
  local parents = build_parents_mapping(graph)
  local path = get_path_to_root(parents, key)
  local path_nodes = {}
  for _, node_key in ipairs(path) do
    path_nodes[node_key] = true
  end
  local tree = {}
  local root_key = path[1]
  tree[root_key] = build_tree(graph, root_key, 0, path_nodes, key, {})
  return tree
end

-- Function to build display lines
function M.build_display_lines(tree, selected_node)
  local lines = {}
  local marks = {}
  local function helper(subtree, indent)
    indent = indent or ""
    for node_key, node in pairs(subtree) do
      local key_values = vim.split(node_key, "/")
      local line = indent .. key_values[1] .. ": " .. key_values[2] .. "/" .. key_values[3]
      local hlgroup = node_key == selected_node and hl.symbols.success_bold or hl.symbols.white_bold

      table.insert(marks, {
        row = #lines,
        start_col = #indent + #key_values[1] + #key_values[2] + 3,
        end_col = #line,
        hl_group = hlgroup,
      })
      table.insert(lines, line)
      if node.children then
        helper(node.children, indent .. "    ")
      end
    end
  end
  helper(tree, "")
  return lines, marks
end
return M
