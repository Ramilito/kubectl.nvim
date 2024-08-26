local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")

local M = {}
local obj_fresh = config.options.obj_fresh
local success_symbol = hl.symbols.success

--- Calculate the time difference since the given timestamp and format it
---@param timestamp string
---@param fresh? boolean
---@param currentTime? number
---@return table|nil
function M.since(timestamp, fresh, currentTime)
  if not timestamp or type(timestamp) ~= "string" then
    return nil
  end

  if not currentTime then
    currentTime = M.currentTime()
  end

  local parsed_time = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", timestamp)

  local diff = currentTime - parsed_time
  local days = math.floor(diff / 86400)
  local years = math.floor(days / 365)
  local hours = math.floor((diff % 86400) / 3600)
  local minutes = math.floor((diff % 3600) / 60)
  local seconds = diff % 60

  local status = { symbol = "", value = "", sort_by = tonumber(parsed_time) }
  if days > 365 then
    status.value = string.format("%dy%dd", years, days % 365)
  elseif days > 7 then
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

  -- vim.print("status: " .. vim.inspect(status))
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
