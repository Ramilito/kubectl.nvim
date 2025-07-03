local M = {}

function M.processRow(rows)
  local data = {}
  for _, v in pairs(rows) do
    if type(v) == "string" then
      return
    end
    table.insert(data, {
      name = v.plural,
      shortnames = "",
      apiversion = v.api_version,
      kind = v.gvk and v.gvk.k or "",
      namespaced = v.namespaced,
    })
  end
  return data
end

return M
