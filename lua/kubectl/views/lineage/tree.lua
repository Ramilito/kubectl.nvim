-- Function to generate a unique key for each resource
local function get_resource_key(resource)
  local kind = string.lower(resource.kind)
  if resource.ns and kind ~= "node" then
    return string.lower(string.format("%s/%s/%s", kind, resource.ns, resource.name))
  else
    return string.lower(string.format("%s/%s", kind, resource.name))
  end
end

local TreeNode = {}
TreeNode.__index = TreeNode

function TreeNode:new(resource)
  local node = {
    resource = resource,
    children = {},
    key = get_resource_key(resource),
    parent = nil,
  }
  setmetatable(node, TreeNode)
  return node
end

function TreeNode:add_child(child_node)
  table.insert(self.children, child_node)
  child_node.parent = self
end

local Tree = {}
Tree.__index = Tree

function Tree:new(root_resource)
  local tree = {
    root = TreeNode:new(root_resource),
    nodes_by_key = {}, -- Lookup table for nodes by unique key
  }
  tree.nodes_by_key[tree.root.key] = tree.root -- Add root node to lookup
  setmetatable(tree, Tree)
  return tree
end

function Tree:add_node(resource)
  local new_node_key = get_resource_key(resource)

  -- If the node already exists, skip
  if self.nodes_by_key[new_node_key] then
    return
  end

  -- Create a new node and add it to the lookup table
  local new_node = TreeNode:new(resource)
  self.nodes_by_key[new_node.key] = new_node
end

function Tree:link_nodes()
  for _, node in pairs(self.nodes_by_key) do
    -- Skip the root node
    if node == self.root then
      node.is_linked = true
    else
      local resource = node.resource

      -- If no owners, add the node as a child of the root
      if not resource.owners or #resource.owners == 0 then
        if not node.is_linked then
          self.root:add_child(node)
          node.is_linked = true
        end
      else
        local owner = resource.owners[1] -- Assuming only one owner
        local owner_key = get_resource_key(owner)
        local owner_node = self.nodes_by_key[owner_key]

        if owner_node and not node.is_linked then
          owner_node:add_child(node)
          node.is_linked = true
        else
          print("Owner not found in the tree for: " .. resource.name)
          print("Owner " .. owner_key .. " not found in the tree for: " .. resource.name)
        end
      end
    end
  end
end

function Tree:get_related_items(node_key)
  -- Look up the node from the tree
  local node = self.nodes_by_key[node_key]

  -- Return early if the node is nil
  if not node then
    print("Error: Node with key " .. node_key .. " is not in the tree.")
    return {}
  end

  local related_nodes = {}
  local visited = {}

  -- Helper function to add nodes if not already visited
  local function add_node(n)
    if n and n.key then -- Ensure the node and its key exist
      if not visited[n.key] then
        table.insert(related_nodes, n)
        visited[n.key] = true
      end
    end
  end

  -- Collect all ancestors (moving up to the root), but skip the root itself
  local current_node = node
  while current_node do
    if current_node ~= self.root then -- Skip the root node
      add_node(current_node) -- Add the current node (ancestor) to related nodes
    end
    current_node = current_node.parent
  end

  -- Helper function to collect all descendants (recursively)
  local function collect_descendants(node)
    for _, child in ipairs(node.children) do
      add_node(child) -- Add child
      collect_descendants(child) -- Recursively collect all descendants
    end
  end

  -- For each ancestor (excluding the root), collect all descendants
  for _, ancestor in ipairs(related_nodes) do
    collect_descendants(ancestor)
  end

  -- Finally, include the selected node itself and its descendants
  add_node(node)
  collect_descendants(node)

  return related_nodes
end

return Tree
