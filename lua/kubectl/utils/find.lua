local M = {}

--- Escape special characters in a string for use in a Lua pattern
---@param s string
---@return string
function M.escape(s)
  local matches = {
    ["^"] = "%^",
    ["$"] = "%$",
    ["("] = "%(",
    [")"] = "%)",
    ["%"] = "%%",
    ["."] = "%.",
    ["["] = "%[",
    ["]"] = "%]",
    ["*"] = "%*",
    ["+"] = "%+",
    ["-"] = "%-",
    ["?"] = "%?",
  }
  return (s:gsub(".", matches))
end

--- Check if a string is in a table, recursively
---@param tbl table
---@param str string
---@return boolean
local function is_in_table(tbl, str)
  if str == nil then
    return true
  end
  for _, value in pairs(tbl) do
    if type(value) == "table" then
      if is_in_table(value, str) then
        return true
      end
    elseif tostring(value):lower():match(str:lower()) then
      return true
    end
  end
  return false
end

--- Filter lines in an array based on a pattern starting from a given index
---@param array table[]
---@param pattern string
---@param startAt number
---@return table[]
function M.filter_line(array, pattern, startAt)
  local filtered_array = {}
  if not pattern then
    return array
  end
  startAt = startAt or 1

  if array then
    for index = 1, startAt - 1 do
      table.insert(filtered_array, array[index])
    end
    for index = startAt, #array do
      local line = array[index]
      if is_in_table(line, pattern) then
        table.insert(filtered_array, line)
      end
    end
  end

  return filtered_array
end

--- Find an item in an array that matches a pattern
---@param array table[]
---@param pattern any
---@return any
function M.array(array, pattern)
  for _, item in ipairs(array) do
    if item == pattern then
      return item
    end
  end
  return nil
end

--- Find a key-value pair in a dictionary that matches a given function
---@param dict table
---@param match_func fun(key: any, value: any): boolean
---@return any, any
function M.dictionary(dict, match_func)
  for key, value in pairs(dict) do
    if match_func(key, value) then
      return key, value
    end
  end
  return nil, nil -- Return nil if no match is found
end

return M
