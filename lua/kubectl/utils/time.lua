local M = {}

-- Function to parse the timestamp
local function parse(timestamp)
  local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z"
  local year, month, day, hour, min, sec = timestamp:match(pattern)
  return os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false, -- Explicitly setting isdst to false
  })
end

-- Function to get the current time in UTC
local function getCurrentTimeUTC()
  return os.time(os.date("!*t"))
end

-- Function to calculate the time difference and format it
function M.since(timestamp)
  if not timestamp or type(timestamp) ~= "string" then
    return "nil"
  end

  local parsedTime = parse(timestamp)
  local currentTime = getCurrentTimeUTC()
  local diff = currentTime - parsedTime

  local seconds = diff % 60
  local minutes = math.floor(diff / 60)
  local hours = math.floor(minutes / 60)
  local days = math.floor(hours / 24)

  minutes = minutes % 60
  hours = hours % 24
  if days > 7 then
    return string.format("%dd", days)
  elseif days > 0 or hours > 23 then
    return string.format("%dd%dh", days, hours)
  else
    return string.format("%dm%ds", minutes, seconds)
  end
end

return M
