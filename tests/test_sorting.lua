-- Feature Tier: Tests resource sorting behavior
-- Guards the user-facing feature of sorting resource tables by column with asc/desc order

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local state = require("kubectl.state")
local factory = require("kubectl.resource_factory")

local T = new_set()

-- Realistic pod rows matching Rust PodProcessed shape from get_table_async
-- FieldValue: { value = string, symbol? = string, sort_by? = number, hint? = string }
local function make_pod(name, ns, status, status_sym, ready, ready_sym, restarts, ip, ip_sort, node, age, age_sort)
  return {
    namespace = ns,
    name = name,
    ready = { value = ready, symbol = ready_sym, sort_by = tonumber(ready:match("^(%d+)")) },
    status = { value = status, symbol = status_sym },
    restarts = { value = tostring(restarts), sort_by = restarts },
    ip = { value = ip, sort_by = ip_sort },
    node = node,
    age = { value = age, sort_by = age_sort },
    cpu = { value = "0", sort_by = 0 },
    mem = { value = "0", sort_by = 0 },
    ["%cpu/r"] = { value = "n/a" },
    ["%cpu/l"] = { value = "n/a" },
    ["%mem/r"] = { value = "n/a" },
    ["%mem/l"] = { value = "n/a" },
  }
end

-- Realistic deployment rows matching Rust DeploymentProcessed
local function make_deploy(name, ns, ready_cur, ready_total, up_to_date, available, age, age_sort)
  local ready_sym = ready_cur == ready_total and "KubectlNote" or "KubectlDeprecated"
  return {
    namespace = ns,
    name = name,
    ready = { value = ready_cur .. "/" .. ready_total, symbol = ready_sym, sort_by = (ready_cur * 1001) + ready_total },
    ["up-to-date"] = up_to_date,
    available = available,
    age = { value = age, sort_by = age_sort },
  }
end

T["sorting"] = new_set()

T["sorting"]["sorts pods ascending by name"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("zebra-app-xyz", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "2h", 1707843000),
    make_pod("alpha-web-abc", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-2", "5d", 1707419000),
    make_pod("beta-api-def", "default", "Pending", "KubectlWarning", "0/1", "KubectlDeprecated", 0, "", 0, "node-1", "30s", 1707851070),
  }
  state.sortby["pods"] = { mark = {}, current_word = "name", order = "asc" }

  builder.sort()

  expect.equality(builder.processedData[1].name, "alpha-web-abc")
  expect.equality(builder.processedData[2].name, "beta-api-def")
  expect.equality(builder.processedData[3].name, "zebra-app-xyz")
end

T["sorting"]["sorts pods descending by name"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("alpha-web-abc", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-1", "5d", 1707419000),
    make_pod("zebra-app-xyz", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-2", "2h", 1707843000),
    make_pod("beta-api-def", "default", "Pending", "KubectlWarning", "0/1", "KubectlDeprecated", 0, "", 0, "node-1", "30s", 1707851070),
  }
  state.sortby["pods"] = { mark = {}, current_word = "name", order = "desc" }

  builder.sort()

  expect.equality(builder.processedData[1].name, "zebra-app-xyz")
  expect.equality(builder.processedData[2].name, "beta-api-def")
  expect.equality(builder.processedData[3].name, "alpha-web-abc")
end

T["sorting"]["sorts deployments by up-to-date count ascending"] = function()
  local builder = factory.new("deployments")
  builder.processedData = {
    make_deploy("web-app", "default", 2, 3, 2, 2, "1d2h", 1707764123),
    make_deploy("api-server", "default", 3, 3, 3, 3, "5d", 1707419723),
    make_deploy("worker", "default", 1, 1, 1, 1, "10d", 1706987323),
  }
  state.sortby["deployments"] = { mark = {}, current_word = "up-to-date", order = "asc" }

  builder.sort()

  expect.equality(builder.processedData[1]["up-to-date"], 1)
  expect.equality(builder.processedData[2]["up-to-date"], 2)
  expect.equality(builder.processedData[3]["up-to-date"], 3)
end

T["sorting"]["sorts pods by age using sort_by timestamp ascending"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("old-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "5d", 1707419000),
    make_pod("new-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-2", "2m", 1707851000),
    make_pod("mid-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.7", 171048711, "node-1", "2h", 1707843000),
  }
  state.sortby["pods"] = { mark = {}, current_word = "age", order = "asc" }

  builder.sort()

  -- sort_by is unix timestamp, ascending means oldest first (lowest timestamp)
  expect.equality(builder.processedData[1].name, "old-pod")
  expect.equality(builder.processedData[2].name, "mid-pod")
  expect.equality(builder.processedData[3].name, "new-pod")
end

T["sorting"]["sorts pods by age descending (newest first)"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("old-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "5d", 1707419000),
    make_pod("new-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-2", "2m", 1707851000),
    make_pod("mid-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.7", 171048711, "node-1", "2h", 1707843000),
  }
  state.sortby["pods"] = { mark = {}, current_word = "age", order = "desc" }

  builder.sort()

  expect.equality(builder.processedData[1].name, "new-pod")
  expect.equality(builder.processedData[2].name, "mid-pod")
  expect.equality(builder.processedData[3].name, "old-pod")
end

T["sorting"]["sorts pods by restarts using sort_by count"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("stable-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "5d", 1707419000),
    make_pod("flaky-pod", "default", "CrashLoopBackOff", "KubectlError", "0/1", "KubectlDeprecated", 10, "10.244.0.5", 171048709, "node-2", "15m", 1707851000),
    make_pod("restarted-pod", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 3, "10.244.0.7", 171048711, "node-1", "2h", 1707843000),
  }
  state.sortby["pods"] = { mark = {}, current_word = "restarts", order = "asc" }

  builder.sort()

  expect.equality(builder.processedData[1].restarts.sort_by, 0)
  expect.equality(builder.processedData[2].restarts.sort_by, 3)
  expect.equality(builder.processedData[3].restarts.sort_by, 10)
end

T["sorting"]["sorts pods by ip using numeric sort_by"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("pod-c", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.2.5", 171049477, "node-1", "1d", 1707764123),
    make_pod("pod-a", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-2", "5d", 1707419000),
    make_pod("pod-b", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.1.10", 171048970, "node-1", "2h", 1707843000),
  }
  state.sortby["pods"] = { mark = {}, current_word = "ip", order = "asc" }

  builder.sort()

  -- IP sort_by is u32 representation: 10.244.0.3 < 10.244.1.10 < 10.244.2.5
  expect.equality(builder.processedData[1].ip.value, "10.244.0.3")
  expect.equality(builder.processedData[2].ip.value, "10.244.1.10")
  expect.equality(builder.processedData[3].ip.value, "10.244.2.5")
end

T["sorting"]["sorts deployment ready field by composite sort_by"] = function()
  local builder = factory.new("deployments")
  builder.processedData = {
    make_deploy("small-app", "default", 1, 1, 1, 1, "10d", 1706987323),
    make_deploy("big-app", "default", 3, 3, 3, 3, "5d", 1707419723),
    make_deploy("scaling-app", "default", 2, 3, 2, 2, "1d2h", 1707764123),
  }
  state.sortby["deployments"] = { mark = {}, current_word = "ready", order = "asc" }

  builder.sort()

  -- sort_by = (available * 1001) + replicas: 1*1001+1=1002, 2*1001+3=2005, 3*1001+3=3006
  expect.equality(builder.processedData[1].name, "small-app")
  expect.equality(builder.processedData[2].name, "scaling-app")
  expect.equality(builder.processedData[3].name, "big-app")
end

T["sorting"]["sorts FieldValue cells by value string when no sort_by"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    { name = "pod-1", status = { value = "Running", symbol = "KubectlSuccess" } },
    { name = "pod-2", status = { value = "CrashLoopBackOff", symbol = "KubectlError" } },
    { name = "pod-3", status = { value = "Pending", symbol = "KubectlWarning" } },
  }
  state.sortby["pods"] = { mark = {}, current_word = "status", order = "asc" }

  builder.sort()

  -- Alphabetical by value: CrashLoopBackOff < Pending < Running
  expect.equality(builder.processedData[1].status.value, "CrashLoopBackOff")
  expect.equality(builder.processedData[2].status.value, "Pending")
  expect.equality(builder.processedData[3].status.value, "Running")
end

T["sorting"]["returns unchanged when sort column is empty string"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("zebra-app", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "2h", 1707843000),
    make_pod("alpha-app", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-2", "5d", 1707419000),
  }
  state.sortby["pods"] = { mark = {}, current_word = "", order = "asc" }

  builder.sort()

  expect.equality(builder.processedData[1].name, "zebra-app")
  expect.equality(builder.processedData[2].name, "alpha-app")
end

T["sorting"]["returns unchanged when sortby is nil for the resource"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("zebra-app", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "2h", 1707843000),
    make_pod("alpha-app", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-2", "5d", 1707419000),
  }
  state.sortby["pods"] = nil

  builder.sort()

  expect.equality(builder.processedData[1].name, "zebra-app")
  expect.equality(builder.processedData[2].name, "alpha-app")
end

T["sorting"]["handles case-insensitive column names"] = function()
  local builder = factory.new("pods")
  builder.processedData = {
    make_pod("zebra-app", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.3", 171048707, "node-1", "2h", 1707843000),
    make_pod("alpha-app", "default", "Running", "KubectlSuccess", "1/1", "KubectlNote", 0, "10.244.0.5", 171048709, "node-2", "5d", 1707419000),
  }
  -- Column header is "NAME" (uppercase) but data key is "name" (lowercase)
  -- The sort function lowercases current_word before lookup
  state.sortby["pods"] = { mark = {}, current_word = "NAME", order = "asc" }

  builder.sort()

  expect.equality(builder.processedData[1].name, "alpha-app")
  expect.equality(builder.processedData[2].name, "zebra-app")
end

T["sorting"]["handles empty processedData"] = function()
  local builder = factory.new("pods")
  builder.processedData = {}
  state.sortby["pods"] = { mark = {}, current_word = "name", order = "asc" }

  builder.sort()

  expect.equality(#builder.processedData, 0)
end

return T
