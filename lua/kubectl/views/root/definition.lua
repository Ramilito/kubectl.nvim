local M = {
  resource = "root",
  display_name = "Root",
  ft = "k8s_root",
  hints = { { key = "<Plug>(kubectl.select)", desc = "Select" } },
}

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows) do
    table.insert(data, { name = row })
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
  }

  return headers
end
return M
