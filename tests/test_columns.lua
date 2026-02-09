-- Feature Tier: Tests column visibility and reordering behavior
-- Guards the user-facing feature of showing/hiding and rearranging table columns

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local tables = require("kubectl.utils.tables")
local state = require("kubectl.state")

local T = new_set()

-- Pod headers matching Rust PodProcessed struct field order
local pod_headers = { "NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "CPU", "MEM", "%CPU/R", "%CPU/L", "%MEM/R", "%MEM/L", "IP", "NODE", "AGE" }
local resource_name = "pods"

-- Deployment headers matching Rust DeploymentProcessed
local deploy_headers = { "NAMESPACE", "NAME", "READY", "UP-TO-DATE", "AVAILABLE", "AGE" }

-- Cleanup helper to reset state between tests
local function cleanup_state()
  state.column_order = {}
  state.column_visibility = {}
end

-- getVisibleHeaders tests
T["getVisibleHeaders"] = new_set()

T["getVisibleHeaders"]["returns all pod headers when no saved order and no visibility overrides"] = function()
  cleanup_state()
  local result = tables.getVisibleHeaders(resource_name, pod_headers)
  expect.equality(#result, #pod_headers)
  for i, header in ipairs(pod_headers) do
    expect.equality(result[i], header)
  end
end

T["getVisibleHeaders"]["reorders pod headers based on saved column order"] = function()
  cleanup_state()
  local new_order = { "NAME", "STATUS", "READY", "AGE", "NAMESPACE", "RESTARTS", "CPU", "MEM", "%CPU/R", "%CPU/L", "%MEM/R", "%MEM/L", "IP", "NODE" }
  state.column_order[resource_name] = new_order

  local result = tables.getVisibleHeaders(resource_name, pod_headers)
  expect.equality(#result, #pod_headers)
  for i, header in ipairs(new_order) do
    expect.equality(result[i], header)
  end
  cleanup_state()
end

T["getVisibleHeaders"]["hides metric columns when marked not visible"] = function()
  cleanup_state()
  state.column_visibility[resource_name] = {
    CPU = false,
    MEM = false,
    ["%CPU/R"] = false,
    ["%CPU/L"] = false,
    ["%MEM/R"] = false,
    ["%MEM/L"] = false,
  }

  local result = tables.getVisibleHeaders(resource_name, pod_headers)
  expect.equality(#result, 8) -- 14 original - 6 hidden metrics

  for _, header in ipairs(result) do
    expect.no_equality(header, "CPU")
    expect.no_equality(header, "MEM")
  end
  cleanup_state()
end

T["getVisibleHeaders"]["never hides required headers even if marked invisible"] = function()
  cleanup_state()
  state.column_visibility[resource_name] = {
    NAME = false,
    NAMESPACE = false,
    STATUS = false,
  }

  local result = tables.getVisibleHeaders(resource_name, pod_headers)

  -- NAME and NAMESPACE are required, should still be present
  local has_name = false
  local has_namespace = false
  for _, header in ipairs(result) do
    if header == "NAME" then
      has_name = true
    end
    if header == "NAMESPACE" then
      has_namespace = true
    end
  end
  expect.equality(has_name, true)
  expect.equality(has_namespace, true)

  -- STATUS is not required, should be hidden
  local has_status = false
  for _, header in ipairs(result) do
    if header == "STATUS" then
      has_status = true
    end
  end
  expect.equality(has_status, false)
  cleanup_state()
end

T["getVisibleHeaders"]["handles missing columns in saved order by appending them"] = function()
  cleanup_state()
  -- Saved order missing several columns
  local partial_order = { "NAME", "STATUS", "AGE", "NAMESPACE" }
  state.column_order[resource_name] = partial_order

  local result = tables.getVisibleHeaders(resource_name, pod_headers)
  expect.equality(#result, #pod_headers)

  -- First 4 should match saved order
  expect.equality(result[1], "NAME")
  expect.equality(result[2], "STATUS")
  expect.equality(result[3], "AGE")
  expect.equality(result[4], "NAMESPACE")
  cleanup_state()
end

T["getVisibleHeaders"]["empty column_order does not change order"] = function()
  cleanup_state()
  state.column_order[resource_name] = {}

  local result = tables.getVisibleHeaders(resource_name, pod_headers)
  for i, header in ipairs(pod_headers) do
    expect.equality(result[i], header)
  end
  cleanup_state()
end

T["getVisibleHeaders"]["works with deployment headers"] = function()
  cleanup_state()
  state.column_visibility["deployments"] = {
    ["UP-TO-DATE"] = false,
    AVAILABLE = false,
  }

  local result = tables.getVisibleHeaders("deployments", deploy_headers)
  expect.equality(#result, 4) -- NAMESPACE, NAME, READY, AGE
  cleanup_state()
end

T["getVisibleHeaders"]["combines reordering and visibility"] = function()
  cleanup_state()
  local new_order = { "NAME", "STATUS", "READY", "AGE", "NAMESPACE", "RESTARTS", "IP", "NODE", "CPU", "MEM", "%CPU/R", "%CPU/L", "%MEM/R", "%MEM/L" }
  state.column_order[resource_name] = new_order
  state.column_visibility[resource_name] = {
    RESTARTS = false,
    IP = false,
    NODE = false,
    CPU = false,
    MEM = false,
    ["%CPU/R"] = false,
    ["%CPU/L"] = false,
    ["%MEM/R"] = false,
    ["%MEM/L"] = false,
  }

  local result = tables.getVisibleHeaders(resource_name, pod_headers)
  expect.equality(#result, 5) -- NAME, STATUS, READY, AGE, NAMESPACE
  expect.equality(result[1], "NAME")
  expect.equality(result[2], "STATUS")
  expect.equality(result[3], "READY")
  expect.equality(result[4], "AGE")
  expect.equality(result[5], "NAMESPACE")
  cleanup_state()
end

-- is_selected tests using realistic Rust row shapes
T["is_selected"] = new_set()

T["is_selected"]["returns true when pod row matches selection"] = function()
  local row = {
    namespace = "default",
    name = "nginx-deployment-7d64f7f5c9-abcd",
    status = { value = "Running", symbol = "KubectlSuccess" },
    ready = { value = "1/1", symbol = "KubectlNote", sort_by = 1 },
  }
  local selections = {
    { name = "nginx-deployment-7d64f7f5c9-abcd", namespace = "default" },
  }
  expect.equality(tables.is_selected(row, selections), true)
end

T["is_selected"]["returns false when pod row doesn't match"] = function()
  local row = {
    namespace = "default",
    name = "nginx-deployment-7d64f7f5c9-abcd",
    status = { value = "Running", symbol = "KubectlSuccess" },
  }
  local selections = {
    { name = "redis-master-0", namespace = "default" },
  }
  expect.equality(tables.is_selected(row, selections), false)
end

T["is_selected"]["returns false for empty selections"] = function()
  local row = { namespace = "default", name = "nginx-pod" }
  expect.equality(tables.is_selected(row, {}), false)
end

T["is_selected"]["returns false for nil selections"] = function()
  local row = { namespace = "default", name = "nginx-pod" }
  expect.equality(tables.is_selected(row, nil), false)
end

T["is_selected"]["matches against multiple selections returns true if any match"] = function()
  local row = { namespace = "default", name = "nginx-pod-abc" }
  local selections = {
    { name = "redis-master-0", namespace = "kube-system" },
    { name = "nginx-pod-abc", namespace = "default" },
    { name = "postgres-db-xyz", namespace = "default" },
  }
  expect.equality(tables.is_selected(row, selections), true)
end

T["is_selected"]["must match ALL keys in selection"] = function()
  local row = {
    namespace = "default",
    name = "nginx-pod-abc",
    status = { value = "Running", symbol = "KubectlSuccess" },
  }
  local selections = {
    { name = "nginx-pod-abc", namespace = "kube-system" }, -- name matches, namespace doesn't
  }
  expect.equality(tables.is_selected(row, selections), false)
end

T["is_selected"]["partial key match returns true if all selection keys match row"] = function()
  local row = {
    namespace = "default",
    name = "nginx-pod-abc",
    status = { value = "Running", symbol = "KubectlSuccess" },
    ready = { value = "1/1", symbol = "KubectlNote", sort_by = 1 },
    age = { value = "5d", sort_by = 1707419000 },
  }
  local selections = {
    { name = "nginx-pod-abc", namespace = "default" }, -- Subset of row keys
  }
  expect.equality(tables.is_selected(row, selections), true)
end

-- find_index tests with actual header arrays
T["find_index"] = new_set()

T["find_index"]["returns index for pod headers"] = function()
  expect.equality(tables.find_index(pod_headers, "STATUS"), 4)
  expect.equality(tables.find_index(pod_headers, "NAMESPACE"), 1)
  expect.equality(tables.find_index(pod_headers, "NAME"), 2)
  expect.equality(tables.find_index(pod_headers, "AGE"), 14)
end

T["find_index"]["returns index for deployment headers"] = function()
  expect.equality(tables.find_index(deploy_headers, "UP-TO-DATE"), 4)
  expect.equality(tables.find_index(deploy_headers, "AVAILABLE"), 5)
end

T["find_index"]["returns nil when not found"] = function()
  expect.equality(tables.find_index(pod_headers, "NONEXISTENT"), nil)
end

T["find_index"]["returns nil for nil haystack"] = function()
  expect.equality(tables.find_index(nil, "NAME"), nil)
end

T["find_index"]["returns nil for empty haystack"] = function()
  expect.equality(tables.find_index({}, "NAME"), nil)
end

return T
