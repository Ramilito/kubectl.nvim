local hl = require("kubectl.actions.highlight")

local M = {}

-- Function to parse the timestamp
-- Function to parse the timestamp
function M.parse(timestamp)
  local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.(%d+)Z"
  local year, month, day, hour, min, sec, frac = timestamp:match(pattern)
  if not frac then
    pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z"
    year, month, day, hour, min, sec = timestamp:match(pattern)
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

-- Function to get the current time in UTC
local function getCurrentTimeUTC()
  return os.time(os.date("!*t"))
end

-- Function to calculate the time difference and format it
function M.since(timestamp, fresh)
  local status = { symbol = "", value = "", timestamp = timestamp }
  if not timestamp or type(timestamp) ~= "string" then
    return nil
  end

  local parsedTime = M.parse(timestamp)
  local currentTime = getCurrentTimeUTC()
  local diff = currentTime - parsedTime

  local seconds = diff % 60
  local minutes = math.floor(diff / 60)
  local hours = math.floor(minutes / 60)
  local days = math.floor(hours / 24)

  minutes = minutes % 60
  hours = hours % 24
  if days > 7 then
    status.value = string.format("%dd", days)
  elseif days > 0 or hours > 23 then
    status.value = string.format("%dd%dh", days, hours)
  else
    if fresh then
      status.symbol = hl.symbols.success
    end
    status.value = string.format("%dm%ds", minutes, seconds)
  end

  return status
end

return M
