local M = {}

M.store = {}

function M.set(key, value)
  M.store[key] = value
end

function M.get(key)
  return M.store[key]
end

function M.has(key)
  return M.store[key] ~= nil
end
return M
