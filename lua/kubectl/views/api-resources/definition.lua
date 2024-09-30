local M = {
  resource = "api-resources",
  display_name = "API Resources",
  ft = "k8s_api_resources",
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "show resource" },
  },
}

function M.processRow(rows)
  local data = {}
  for _, v in pairs(rows) do
    if type(v) == "string" then
      return
    end
    local res = vim.deepcopy(v)
    res.url = nil
    res.namespaced = tostring(v.namespaced)
    if v.kind ~= nil then
      table.insert(data, res)
    end
  end
  return data
end

function M.getHeaders()
  return {
    "NAME",
    "KIND",
    "NAMESPACED",
    "VERSION",
  }
end

return M
