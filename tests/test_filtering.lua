-- Feature Tier: Tests resource filtering behavior
-- Guards the user-facing feature of filtering resource lists with patterns

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local find = require("kubectl.utils.find")

local T = new_set()

-- Realistic pod rows matching Rust PodProcessed shape from get_table_async
-- Fields use FieldValue { value, symbol, sort_by, hint } for rich cells
local rows = {
  {
    namespace = "default",
    name = "nginx-pod-1",
    ready = { value = "1/1", symbol = "KubectlNote", sort_by = 1 },
    status = { value = "Running", symbol = "KubectlSuccess" },
    restarts = { value = "0", sort_by = 0 },
    ip = { value = "10.244.0.42", sort_by = 171048746 },
    node = "node-1",
    age = { value = "2h30m", sort_by = 1707850123 },
  },
  {
    namespace = "default",
    name = "nginx-pod-2",
    ready = { value = "0/1", symbol = "KubectlDeprecated", sort_by = 0 },
    status = { value = "Pending", symbol = "KubectlWarning" },
    restarts = { value = "0", sort_by = 0 },
    ip = { value = "", sort_by = 0 },
    node = "node-1",
    age = { value = "30s", sort_by = 1707851070 },
  },
  {
    namespace = "kube-system",
    name = "redis-master",
    ready = { value = "1/1", symbol = "KubectlNote", sort_by = 1 },
    status = { value = "Running", symbol = "KubectlSuccess" },
    restarts = { value = "2 (1h ago)", sort_by = 2, symbol = "KubectlWarning" },
    ip = { value = "10.244.1.10", sort_by = 171048970 },
    node = "node-2",
    age = { value = "5d", sort_by = 1707419000 },
  },
  {
    namespace = "default",
    name = "postgres-db",
    ready = { value = "0/1", symbol = "KubectlDeprecated", sort_by = 0 },
    status = { value = "CrashLoopBackOff", symbol = "KubectlError" },
    restarts = { value = "10 (1m ago)", sort_by = 10, symbol = "KubectlWarning" },
    ip = { value = "10.244.0.55", sort_by = 171048759 },
    node = "node-2",
    age = { value = "15m", sort_by = 1707851000 },
  },
  {
    namespace = "ingress-ns",
    name = "nginx-ingress",
    ready = { value = "1/1", symbol = "KubectlNote", sort_by = 1 },
    status = { value = "Running", symbol = "KubectlSuccess" },
    restarts = { value = "0", sort_by = 0 },
    ip = { value = "10.244.2.5", sort_by = 171049477 },
    node = "node-1",
    age = { value = "10d", sort_by = 1706987323 },
  },
}

T["filtering"] = new_set()

T["filtering"]["returns all rows when filter is empty"] = function()
  local result = find.filter_line(rows, "", 1)
  expect.equality(#result, #rows)
end

T["filtering"]["returns all rows when filter is nil"] = function()
  local result = find.filter_line(rows, nil, 1)
  expect.equality(#result, #rows)
end

T["filtering"]["matches rows containing pattern in name field"] = function()
  local result = find.filter_line(rows, "nginx", 1)
  expect.equality(#result, 3) -- nginx-pod-1, nginx-pod-2, nginx-ingress
end

T["filtering"]["match is case-insensitive"] = function()
  local result = find.filter_line(rows, "NGINX", 1)
  expect.equality(#result, 3)
end

T["filtering"]["excludes rows with ! prefix"] = function()
  local result = find.filter_line(rows, "!nginx", 1)
  expect.equality(#result, 2) -- redis-master, postgres-db
end

T["filtering"]["matches FieldValue cells recursively"] = function()
  -- "Running" lives inside status = { value = "Running", symbol = "..." }
  local result = find.filter_line(rows, "running", 1)
  expect.equality(#result, 3) -- nginx-pod-1, redis-master, nginx-ingress
end

T["filtering"]["matches by namespace"] = function()
  local result = find.filter_line(rows, "kube-system", 1)
  expect.equality(#result, 1) -- redis-master
end

T["filtering"]["combines multiple patterns with comma (AND logic)"] = function()
  local result = find.filter_line(rows, "nginx,running", 1)
  expect.equality(#result, 2) -- nginx-pod-1 and nginx-ingress (both have nginx AND running)
end

T["filtering"]["combines include and exclude patterns"] = function()
  local result = find.filter_line(rows, "running,!nginx", 1)
  expect.equality(#result, 1) -- only redis-master
end

T["filtering"]["matches error status in FieldValue"] = function()
  local result = find.filter_line(rows, "CrashLoopBackOff", 1)
  expect.equality(#result, 1)
  expect.equality(result[1].name, "postgres-db")
end

T["filtering"]["respects startAt index"] = function()
  local result = find.filter_line(rows, "nginx", 3)
  expect.equality(#result, 1) -- only nginx-ingress (index 5), skips rows 1-2
end

T["filtering"]["returns empty table for no matches"] = function()
  local result = find.filter_line(rows, "nonexistent", 1)
  expect.equality(#result, 0)
end

T["filtering"]["handles nil input table"] = function()
  local result = find.filter_line(nil, "test", 1)
  expect.equality(#result, 0)
end

return T
