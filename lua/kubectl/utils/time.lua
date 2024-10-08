local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")

local M = {}
local obj_fresh = config.options.obj_fresh
local success_symbol = hl.symbols.success

--- Get a string representation of the time difference between two timestamps
---@param timeA number more recent timestamp
---@param timeB number older timestamp
---@return string diff_str
---@return boolean is_fresh
function M.diff_str(timeA, timeB)
  local diff = timeA - timeB
  local days = math.floor(diff / 86400)
  local years = math.floor(days / 365)
  local hours = math.floor((diff % 86400) / 3600)
  local minutes = math.floor((diff % 3600) / 60)
  local seconds = diff % 60

  local fresh = math.floor(diff / 60)
  local diff_str = ""
  if days > 365 then
    diff_str = string.format("%dy%dd", years, days % 365)
  elseif days > 7 then
    diff_str = string.format("%dd", days)
  elseif days > 0 or hours > 23 then
    diff_str = string.format("%dd%dh", days, hours)
  elseif hours > 0 then
    diff_str = string.format("%dh%dm", hours, minutes)
  else
    diff_str = string.format("%dm%ds", minutes, seconds)
  end

  return diff_str, obj_fresh > fresh
end

--- Calculate the time difference since the given timestamp and format it
---@param timestamp string
---@param fresh? boolean
---@param currentTime? number
---@param format? string
---@return table|nil
function M.since(timestamp, fresh, currentTime, format)
  if not timestamp or type(timestamp) ~= "string" then
    return nil
  end

  if not currentTime then
    currentTime = M.currentTime()
  end

  if not format then
    format = "%Y-%m-%dT%H:%M:%SZ"
  end

  local parsed_time = vim.fn.strptime(format, timestamp)
  if not parsed_time or parsed_time == 0 then
    return nil
  end
  local diff_str, is_fresh = M.diff_str(currentTime, parsed_time)
  local status = { symbol = "", value = diff_str, sort_by = tonumber(parsed_time) }
  if fresh and is_fresh then
    status.symbol = success_symbol
  end
  return status
end

--- Get the current time in os.time format
---@return number
function M.currentTime()
  local date = os.date("!*t")
  return os.time({
    year = date.year,
    month = date.month,
    day = date.day,
    hour = date.hour,
    min = date.min,
    sec = date.sec,
  })
end

return M
