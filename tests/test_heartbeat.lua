-- Feature Tier: Tests heartbeat display in resource view headers
-- Guards the user-facing feature of showing cluster API server health status

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local config = require("kubectl.config")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local hl = require("kubectl.actions.highlight")

local T = new_set()

-- Configure headers to only produce heartbeat output
-- hints=false and context=false scope the test to heartbeat behavior only
local function setup_config()
  config.options.headers.enabled = true
  config.options.headers.hints = false
  config.options.headers.context = false
  config.options.headers.heartbeat = true
  config.options.headers.skew = { enabled = false }
end

--- Extract virt_text strings from heartbeat mark
local function get_heartbeat_mark(marks)
  for _, mark in ipairs(marks) do
    if mark.virt_text and mark.virt_text_pos == "right_align" then
      return mark
    end
  end
  return nil
end

T["heartbeat"] = new_set()

T["heartbeat"]["shows ok when API server is healthy"] = function()
  setup_config()
  state.livez = { ok = true, time_of_ok = os.time() }

  local _, marks = tables.generateHeader({}, false, true)
  local hb = get_heartbeat_mark(marks)

  expect.no_equality(hb, nil)
  ---@cast hb -nil
  expect.equality(hb.virt_text[1][1], "Heartbeat: ")
  expect.equality(hb.virt_text[1][2], hl.symbols.note)
  expect.equality(hb.virt_text[2][1], "ok")
  expect.equality(hb.virt_text[2][2], hl.symbols.success)
end

T["heartbeat"]["shows pending when health is unknown"] = function()
  setup_config()
  state.livez = { ok = nil, time_of_ok = os.time() }

  local _, marks = tables.generateHeader({}, false, true)
  local hb = get_heartbeat_mark(marks)

  expect.no_equality(hb, nil)
  ---@cast hb -nil
  expect.equality(hb.virt_text[2][1], "pending")
  expect.equality(hb.virt_text[2][2], hl.symbols.warning)
end

T["heartbeat"]["shows failed with elapsed time when API server is down"] = function()
  setup_config()
  -- API was last ok 120 seconds ago
  state.livez = { ok = false, time_of_ok = os.time() - 120 }

  local _, marks = tables.generateHeader({}, false, true)
  local hb = get_heartbeat_mark(marks)

  expect.no_equality(hb, nil)
  ---@cast hb -nil
  expect.equality(hb.virt_text[1][1], "Heartbeat: ")
  expect.equality(hb.virt_text[2][1], "failed ")
  expect.equality(hb.virt_text[2][2], hl.symbols.error)
  -- Third element is "(2m0s)" or similar, verify it contains parentheses
  local elapsed = hb.virt_text[3][1]
  expect.equality(elapsed:sub(1, 1), "(")
  expect.equality(elapsed:sub(-1), ")")
  expect.equality(hb.virt_text[3][2], hl.symbols.error)
end

T["heartbeat"]["is not shown when heartbeat config is disabled"] = function()
  setup_config()
  config.options.headers.heartbeat = false
  state.livez = { ok = true, time_of_ok = os.time() }

  local _, marks = tables.generateHeader({}, false, true)
  local hb = get_heartbeat_mark(marks)

  expect.equality(hb, nil)
end

T["heartbeat"]["is not shown when headers are disabled"] = function()
  setup_config()
  config.options.headers.enabled = false
  state.livez = { ok = true, time_of_ok = os.time() }

  local _, marks = tables.generateHeader({}, false, true)
  expect.equality(#marks, 0)
end

return T
