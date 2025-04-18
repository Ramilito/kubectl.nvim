local Tree = require("kubectl.views.lineage.tree")
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
  local tree = Tree:new({ kind = "cluster", name = context.clusters[1].name })

  for _, item in ipairs(data) do
    tree:add_node(item)
  end
  tree:link_nodes()

  return tree
end

function M.build_display_lines(tree, selected_node_key)
  local lines = {}
  local marks = {}

  local related_nodes = tree:get_related_items(selected_node_key)

  local node_lookup = {}
  for _, node in ipairs(related_nodes) do
    node_lookup[node.key] = node
  end

  -- Find the root ancestor of the selected node
  local selected_node = node_lookup[selected_node_key]
  local root_node = selected_node
  while root_node and root_node.parent do
    root_node = root_node.parent
  end

  local function build_lines(node, indent)
    indent = indent or ""

    -- Skip the root node
    if node == root_node then
      -- Still need to display the children of the root node, so recurse over them
      for _, child in ipairs(node.children) do
        if node_lookup[child.key] then
          build_lines(child, indent) -- No indentation change for root's children
        end
      end
      return
    end

    local key_values = {
      node.resource.kind,
      node.resource.ns or "cluster",
      node.resource.name,
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
    for _, child in ipairs(node.children) do
      if node_lookup[child.key] then
        build_lines(child, indent .. "    ") -- Add indentation for children
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
