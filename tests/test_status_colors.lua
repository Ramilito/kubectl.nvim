-- Feature Tier: Tests status coloring for Kubernetes resource statuses
-- Tests that M.ColorStatus maps statuses to correct highlight groups

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")

local T = new_set()

T["status coloring"] = new_set()

-- Success statuses (green/cyan)
T["status coloring"]["returns success highlight for Running status"] = function()
  local result = events.ColorStatus("Running")
  expect.equality(result, hl.symbols.success)
end

T["status coloring"]["returns success highlight for Completed status"] = function()
  local result = events.ColorStatus("Completed")
  expect.equality(result, hl.symbols.success)
end

T["status coloring"]["returns success highlight for NodeReady status"] = function()
  local result = events.ColorStatus("NodeReady")
  expect.equality(result, hl.symbols.success)
end

-- Error statuses (red)
T["status coloring"]["returns error highlight for CrashLoopBackOff status"] = function()
  local result = events.ColorStatus("CrashLoopBackOff")
  expect.equality(result, hl.symbols.error)
end

T["status coloring"]["returns error highlight for OOMKilled status"] = function()
  local result = events.ColorStatus("OOMKilled")
  expect.equality(result, hl.symbols.error)
end

T["status coloring"]["returns error highlight for ImagePullBackOff status"] = function()
  local result = events.ColorStatus("ImagePullBackOff")
  expect.equality(result, hl.symbols.error)
end

T["status coloring"]["returns error highlight for Init:ErrImagePull status with colon"] = function()
  local result = events.ColorStatus("Init:ErrImagePull")
  expect.equality(result, hl.symbols.error)
end

-- Warning statuses (orange/yellow)
T["status coloring"]["returns warning highlight for Pending status"] = function()
  local result = events.ColorStatus("Pending")
  expect.equality(result, hl.symbols.warning)
end

T["status coloring"]["returns warning highlight for Terminating status"] = function()
  local result = events.ColorStatus("Terminating")
  expect.equality(result, hl.symbols.warning)
end

T["status coloring"]["returns warning highlight for ContainerCreating status"] = function()
  local result = events.ColorStatus("ContainerCreating")
  expect.equality(result, hl.symbols.warning)
end

-- Case handling
T["status coloring"]["handles lowercase input by capitalizing"] = function()
  local result = events.ColorStatus("running")
  expect.equality(result, hl.symbols.success)
end

-- Unknown/invalid inputs
T["status coloring"]["returns empty string for unknown status"] = function()
  local result = events.ColorStatus("NotARealStatus")
  expect.equality(result, "")
end

T["status coloring"]["returns empty string for non-string input"] = function()
  local result = events.ColorStatus(123)
  expect.equality(result, "")
end

return T
