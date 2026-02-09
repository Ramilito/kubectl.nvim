-- Feature Tier: Tests lineage tree view displaying resource ownership relationships
-- Guards the user-facing feature of rendering ownership trees and orphan resources

local new_set = MiniTest.new_set
local expect = MiniTest.expect

-- Set up highlight groups before requiring renderer
require("kubectl.actions.highlight").setup()

local renderer = require("kubectl.views.lineage.renderer")
local RenderContext = renderer.RenderContext

local T = new_set()

-- ---------------------------------------------------------------------------
-- RenderContext API tests
-- ---------------------------------------------------------------------------

T["RenderContext"] = new_set()

T["RenderContext"]["builds lines and marks"] = function()
  local ctx = RenderContext.new()
  ctx:line("First line")
  ctx:mark(0, 5, "TestHighlight")
  ctx:line("Second line")

  local result = ctx:get()

  expect.equality(#result.lines, 2)
  expect.equality(result.lines[1], "First line")
  expect.equality(result.lines[2], "Second line")
  expect.equality(#result.marks, 1)
  expect.equality(result.marks[1].row, 0)
  expect.equality(result.marks[1].start_col, 0)
  expect.equality(result.marks[1].end_col, 5)
  expect.equality(result.marks[1].hl_group, "TestHighlight")
end

T["RenderContext"]["resource_line formats Kind: ns/name with highlights"] = function()
  local ctx = RenderContext.new()
  local node = {
    key = "pod/default/test-pod",
    kind = "Pod",
    ns = "default",
    name = "test-pod",
  }

  ctx:resource_line(node, {})

  local result = ctx:get()

  expect.equality(result.lines[1], "Pod: default/test-pod")
  -- Should have 3 marks: Kind (white), ": namespace/" (gray), name (white)
  expect.equality(#result.marks, 3)
  -- Kind highlight
  expect.equality(result.marks[1].start_col, 0)
  expect.equality(result.marks[1].end_col, 3)
  -- Separator + namespace highlight
  expect.equality(result.marks[2].start_col, 3)
  expect.equality(result.marks[2].end_col, 13) -- ": default/"
  -- Name highlight
  expect.equality(result.marks[3].start_col, 13)
  expect.equality(result.marks[3].end_col, 21)
end

T["RenderContext"]["resource_line handles cluster-scoped resources"] = function()
  local ctx = RenderContext.new()
  local node = {
    key = "namespace/cluster/kube-system",
    kind = "Namespace",
    ns = vim.NIL, -- cluster-scoped
    name = "kube-system",
  }

  ctx:resource_line(node, {})

  local result = ctx:get()

  -- Should default to "cluster" when ns is vim.NIL
  expect.equality(result.lines[1], "Namespace: cluster/kube-system")
end

T["RenderContext"]["resource_line highlights selected node with success_bold"] = function()
  local ctx = RenderContext.new()
  local node = {
    key = "pod/default/selected-pod",
    kind = "Pod",
    ns = "default",
    name = "selected-pod",
  }

  ctx:resource_line(node, { selected_key = "pod/default/selected-pod" })

  local result = ctx:get()

  -- First mark should use success_bold for kind, third for name
  expect.equality(result.marks[1].hl_group, "KubectlSuccessBold")
  expect.equality(result.marks[3].hl_group, "KubectlSuccessBold")
end

T["RenderContext"]["kind_header formats Kind (count)"] = function()
  local ctx = RenderContext.new()
  ctx:kind_header("Pod", 5)

  local result = ctx:get()

  expect.equality(result.lines[1], "Pod (5)")
  expect.equality(#result.marks, 2)
  -- Kind in white
  expect.equality(result.marks[1].start_col, 0)
  expect.equality(result.marks[1].end_col, 3)
  expect.equality(result.marks[1].hl_group, "KubectlWhite")
  -- Count in gray
  expect.equality(result.marks[2].start_col, 3)
  expect.equality(result.marks[2].end_col, 7) -- " (5)"
  expect.equality(result.marks[2].hl_group, "KubectlGray")
end

-- ---------------------------------------------------------------------------
-- render_status tests
-- ---------------------------------------------------------------------------

T["render_status"] = new_set()

T["render_status"]["renders loading progress"] = function()
  local ctx = RenderContext.new()
  renderer.render_status(ctx, "loading", {50, 100})

  local result = ctx:get()

  expect.equality(#result.lines, 5) -- message, blank, progress, blank, wait message
  expect.equality(result.lines[1], "Loading lineage data...")
  expect.equality(result.lines[3], "Progress: 50/100 (50%)")
end

T["render_status"]["renders building message"] = function()
  local ctx = RenderContext.new()
  renderer.render_status(ctx, "building", nil)

  local result = ctx:get()

  expect.equality(result.lines[1], "Building lineage graph...")
  expect.equality(result.lines[3], "Analyzing resource relationships...")
end

T["render_status"]["renders empty message"] = function()
  local ctx = RenderContext.new()
  renderer.render_status(ctx, "empty", nil)

  local result = ctx:get()

  expect.equality(result.lines[1], "No graph available. Press r to refresh.")
end

-- ---------------------------------------------------------------------------
-- render_error tests
-- ---------------------------------------------------------------------------

T["render_error"] = new_set()

T["render_error"]["renders error with highlight"] = function()
  local ctx = RenderContext.new()
  renderer.render_error(ctx, "Connection timeout")

  local result = ctx:get()

  expect.equality(result.lines[1], "Error: Connection timeout")
  expect.equality(result.lines[3], "Press gr to retry.")
  -- Error prefix should be highlighted
  expect.equality(result.marks[1].start_col, 0)
  expect.equality(result.marks[1].end_col, 6) -- "Error:"
  expect.equality(result.marks[1].hl_group, "KubectlError")
end

-- ---------------------------------------------------------------------------
-- render_header tests
-- ---------------------------------------------------------------------------

T["render_header"] = new_set()

T["render_header"]["renders cache timestamp"] = function()
  local ctx = RenderContext.new()
  local timestamp = 1707850000 -- Some Unix timestamp

  renderer.render_header(ctx, timestamp, false, false)

  local result = ctx:get()

  expect.equality(#result.header_data, 1)
  -- Should contain timestamp
  expect.no_equality(result.header_data[1]:find("Cache refreshed at:"), nil)
end

T["render_header"]["shows orphan filter indicator"] = function()
  local ctx = RenderContext.new()

  renderer.render_header(ctx, nil, false, true)

  local result = ctx:get()

  expect.equality(#result.header_data, 1)
  expect.no_equality(result.header_data[1]:find("%[Orphans Only%]"), nil)
end

T["render_header"]["renders loading state without timestamp"] = function()
  local ctx = RenderContext.new()

  renderer.render_header(ctx, nil, true, false)

  local result = ctx:get()

  expect.equality(result.header_data[1], "Associated Resources")
end

-- ---------------------------------------------------------------------------
-- render_orphans tests
-- ---------------------------------------------------------------------------

T["render_orphans"] = new_set()

T["render_orphans"]["groups orphans by kind"] = function()
  local ctx = RenderContext.new()
  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      { key = "pod/default/orphan-1", kind = "Pod", ns = "default", name = "orphan-1", is_orphan = true },
      { key = "pod/default/orphan-2", kind = "Pod", ns = "default", name = "orphan-2", is_orphan = true },
      { key = "service/default/orphan-svc", kind = "Service", ns = "default", name = "orphan-svc", is_orphan = true },
    },
  }

  renderer.render_orphans(ctx, graph)

  local result = ctx:get()

  -- Should have warning line, blank, Pod header, 2 pods, blank, Service header, 1 service
  expect.equality(#result.lines > 7, true)

  -- Check for kind headers
  local has_pod_header = false
  local has_service_header = false
  for _, line in ipairs(result.lines) do
    if line:match("^Pod %(%d+%)") then
      has_pod_header = true
    end
    if line:match("^Service %(%d+%)") then
      has_service_header = true
    end
  end
  expect.equality(has_pod_header, true)
  expect.equality(has_service_header, true)
end

T["render_orphans"]["sorts kinds alphabetically"] = function()
  local ctx = RenderContext.new()
  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      { key = "service/default/svc", kind = "Service", ns = "default", name = "svc", is_orphan = true },
      { key = "deployment/default/deploy", kind = "Deployment", ns = "default", name = "deploy", is_orphan = true },
      { key = "pod/default/pod", kind = "Pod", ns = "default", name = "pod", is_orphan = true },
    },
  }

  renderer.render_orphans(ctx, graph)

  local result = ctx:get()

  -- Find kind header lines and verify order
  local kind_order = {}
  for _, line in ipairs(result.lines) do
    if line:match("^Deployment %(%d+%)") then
      table.insert(kind_order, "Deployment")
    elseif line:match("^Pod %(%d+%)") then
      table.insert(kind_order, "Pod")
    elseif line:match("^Service %(%d+%)") then
      table.insert(kind_order, "Service")
    end
  end

  expect.equality(kind_order[1], "Deployment")
  expect.equality(kind_order[2], "Pod")
  expect.equality(kind_order[3], "Service")
end

T["render_orphans"]["shows no orphans message when none exist"] = function()
  local ctx = RenderContext.new()
  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      { key = "pod/default/normal-pod", kind = "Pod", ns = "default", name = "normal-pod", is_orphan = false },
    },
  }

  renderer.render_orphans(ctx, graph)

  local result = ctx:get()

  expect.equality(result.lines[1], "No orphan resources found.")
end

-- ---------------------------------------------------------------------------
-- render_tree tests
-- ---------------------------------------------------------------------------

T["render_tree"] = new_set()

T["render_tree"]["renders selected node with success highlight"] = function()
  local ctx = RenderContext.new()
  local selected_key = "pod/default/selected-pod"

  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      { key = "cluster/my-cluster", kind = "Cluster", name = "my-cluster", children_keys = {selected_key} },
      { key = selected_key, kind = "Pod", ns = "default", name = "selected-pod", parent_key = "cluster/my-cluster", children_keys = {} },
    },
    get_related_nodes = function(key)
      if key == selected_key then
        return {selected_key}
      end
      return {}
    end,
  }

  renderer.render_tree(ctx, graph, selected_key)

  local result = ctx:get()

  -- Selected node should have success_bold highlights
  local has_success_bold = false
  for _, mark in ipairs(result.marks) do
    if mark.hl_group == "KubectlSuccessBold" then
      has_success_bold = true
      break
    end
  end
  expect.equality(has_success_bold, true)
end

T["render_tree"]["renders ownership tree with parent-child structure"] = function()
  local ctx = RenderContext.new()
  local selected_key = "pod/default/nginx-pod"

  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      {
        key = "cluster/my-cluster",
        kind = "Cluster",
        name = "my-cluster",
        children_keys = {"deployment/default/nginx"}
      },
      {
        key = "deployment/default/nginx",
        kind = "Deployment",
        ns = "default",
        name = "nginx",
        parent_key = "cluster/my-cluster",
        children_keys = {"replicaset/default/nginx-abc"}
      },
      {
        key = "replicaset/default/nginx-abc",
        kind = "ReplicaSet",
        ns = "default",
        name = "nginx-abc",
        parent_key = "deployment/default/nginx",
        children_keys = {selected_key}
      },
      {
        key = selected_key,
        kind = "Pod",
        ns = "default",
        name = "nginx-pod",
        parent_key = "replicaset/default/nginx-abc",
        children_keys = {}
      },
    },
    get_related_nodes = function(key)
      if key == selected_key then
        return {
          "deployment/default/nginx",
          "replicaset/default/nginx-abc",
          selected_key,
        }
      end
      return {}
    end,
  }

  renderer.render_tree(ctx, graph, selected_key)

  local result = ctx:get()

  -- Should have 3 lines (Deployment, ReplicaSet, Pod) - cluster root is skipped
  expect.equality(#result.lines, 3)

  -- First line should be Deployment with no indent
  expect.equality(result.lines[1]:match("^Deployment:"), "Deployment:")

  -- Second line should be ReplicaSet with tree character
  expect.no_equality(result.lines[2]:find("ReplicaSet:"), nil)

  -- Third line should be Pod with deeper indentation
  expect.no_equality(result.lines[3]:find("Pod:"), nil)

  -- Verify line_nodes mapping
  expect.equality(result.line_nodes[1].kind, "Deployment")
  expect.equality(result.line_nodes[2].kind, "ReplicaSet")
  expect.equality(result.line_nodes[3].kind, "Pod")
end

T["render_tree"]["shows reference nodes outside tree"] = function()
  local ctx = RenderContext.new()
  local selected_key = "pod/default/main-pod"

  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      {
        key = "cluster/my-cluster",
        kind = "Cluster",
        name = "my-cluster",
        children_keys = {selected_key, "service/default/my-svc"}
      },
      {
        key = selected_key,
        kind = "Pod",
        ns = "default",
        name = "main-pod",
        parent_key = "cluster/my-cluster",
        children_keys = {}
      },
      {
        key = "service/default/my-svc",
        kind = "Service",
        ns = "default",
        name = "my-svc",
        parent_key = "cluster/my-cluster",
        children_keys = {}
      },
    },
    get_related_nodes = function(key)
      if key == selected_key then
        -- Pod is related to Service (e.g., via label selector), but not in ownership tree
        return {selected_key, "service/default/my-svc"}
      end
      return {}
    end,
  }

  renderer.render_tree(ctx, graph, selected_key)

  local result = ctx:get()

  -- Should have 2 lines: Pod and Service
  expect.equality(#result.lines, 2)

  -- Both should be at root level (no tree characters at start)
  expect.equality(result.lines[1]:match("^Pod:"), "Pod:")
  expect.equality(result.lines[2]:match("^Service:"), "Service:")
end

T["render_tree"]["handles nodes with vim.NIL parent_key"] = function()
  local ctx = RenderContext.new()
  local selected_key = "namespace/cluster/default"

  local graph = {
    root_key = "cluster/my-cluster",
    nodes = {
      {
        key = "cluster/my-cluster",
        kind = "Cluster",
        name = "my-cluster",
        children_keys = {selected_key}
      },
      {
        key = selected_key,
        kind = "Namespace",
        ns = vim.NIL,
        name = "default",
        parent_key = vim.NIL, -- cluster-scoped resource
        children_keys = {}
      },
    },
    get_related_nodes = function(key)
      if key == selected_key then
        return {selected_key}
      end
      return {}
    end,
  }

  renderer.render_tree(ctx, graph, selected_key)

  local result = ctx:get()

  -- Should render successfully with "cluster" as namespace
  expect.equality(#result.lines, 1)
  expect.equality(result.lines[1], "Namespace: cluster/default")
end

return T
