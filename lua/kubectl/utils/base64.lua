local M = {}

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do
  b64lookup[b64chars:sub(i, i)] = i - 1
end

function M.base64decode(data)
  local result = {}
  local padding = 0

  if data:sub(-2) == "==" then
    padding = 2
  elseif data:sub(-1) == "=" then
    padding = 1
  end

  for i = 1, #data, 4 do
    local a = b64lookup[data:sub(i, i)] or 0
    local b = b64lookup[data:sub(i + 1, i + 1)] or 0
    local c = b64lookup[data:sub(i + 2, i + 2)] or 0
    local d = b64lookup[data:sub(i + 3, i + 3)] or 0

    -- Lua 5.1 doesn't have bitwise operators, so we'll use a workaround
    local byte1 = (a * 4) + math.floor(b / 16)
    local byte2 = ((b % 16) * 16) + math.floor(c / 4)
    local byte3 = ((c % 4) * 64) + d

    table.insert(result, string.char(byte1))
    if i + 2 <= #data then
      table.insert(result, string.char(byte2))
    end
    if i + 3 <= #data then
      table.insert(result, string.char(byte3))
    end
  end

  return table.concat(result):sub(1, #result - padding)
end

return M
