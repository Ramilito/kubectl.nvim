local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")

local M = {}
local pattern_with_frac = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.(%d+)Z"
local pattern_without_frac = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z"
local obj_fresh = config.options.obj_fresh
local success_symbol = hl.symbols.success

function M.parse(timestamp)
  local year, month, day, hour, min, sec, frac
  year, month, day, hour, min, sec, frac = timestamp:match(pattern_with_frac)

  if not frac then
    year, month, day, hour, min, sec = timestamp:match(pattern_without_frac)
    frac = 0
  end

  return os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false, -- Explicitly setting isdst to false
  }) + frac / 1000000
end

-- Function to calculate the time difference and format it
function M.since(timestamp, fresh)
  if not timestamp or type(timestamp) ~= "string" then
    return nil
  end

  local parsedTime = M.parse(timestamp)
  local currentTime = os.time(os.date("!*t"))
  local diff = currentTime - parsedTime

  local days = math.floor(diff / 86400)
  local hours = math.floor((diff % 86400) / 3600)
  local minutes = math.floor((diff % 3600) / 60)
  local seconds = diff % 60

  local status = { symbol = "", value = "", timestamp = timestamp }
  if days > 7 then
    status.value = string.format("%dd", days)
  elseif days > 0 or hours > 23 then
    status.value = string.format("%dd%dh", days, hours)
  elseif hours > 0 then
    status.value = string.format("%dh%dm", hours, minutes)
  else
    status.value = string.format("%dm%ds", minutes, seconds)
  end

  if fresh and obj_fresh > math.floor(diff / 60) then
    status.symbol = success_symbol
  end

  return status
end

return M
