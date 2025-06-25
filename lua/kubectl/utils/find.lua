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
---@param exact boolean
---@return boolean
function M.is_in_table(tbl, str, exact)
  if str == nil then
    return false
  end

  local lowered_str = str:lower()
  for _, value in pairs(tbl) do
    if type(value) == "table" then
      if M.is_in_table(value, str, false) then
        return true
      end
    end
    if exact and tostring(value):lower() == lowered_str then
      return true
    elseif not exact and tostring(value):lower():find(lowered_str, 1, true) then
      return true
    end
  end
  return false
end

function M.single(tbl, keys, value)
  if not tbl then
    return nil
  end
  for _, v in ipairs(tbl) do
    local current = v
    for _, key in ipairs(keys) do
      current = current[key]
      if current == nil then
        break
      end
    end
    if current == value then
      return v
    end
  end
  return nil
end

---@param tbl table
---@param predicate table
---@return table
function M.filter(tbl, predicate)
  local result = {}
  for _, v in ipairs(tbl) do
    if predicate(v) then
      table.insert(result, v)
    end
  end
  return result
end

--- Filter lines in an array based on multiple patterns starting from a given index
---@param array table[]
---@param patterns string
---@param startAt number
---@return table[]
function M.filter_line(array, patterns, startAt)
  if not array then
    array = {}
  end
  if not patterns or patterns == "" then
    return array
  end

  startAt = startAt or 1
  local filtered_array = {}
  local pattern_list = {}

  -- Split the patterns by comma
  for pattern in patterns:gmatch("[^,]+") do
    table.insert(pattern_list, pattern)
  end

  -- Filter the array starting from startAt
  for index = startAt, #array do
    local line = array[index]
    local all_match = true

    for _, pattern in ipairs(pattern_list) do
      local is_negative = pattern:sub(1, 1) == "!"
      local actual_pattern = is_negative and pattern:sub(2) or pattern
      local match = M.is_in_table(line, actual_pattern, false)

      if (is_negative and match) or (not is_negative and not match) then
        all_match = false
      end
    end

    if all_match then
      table.insert(filtered_array, line)
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

--- Find index of an item in an array that matches a pattern
function M.tbl_idx(tbl, pattern)
  for idx, item in ipairs(tbl) do
    if item == pattern then
      return idx
    end
  end
  return nil -- Return nil if no match is found
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
