local M = {}

function M.processRow(rows)
  local data = {}
  for _, v in pairs(rows) do
    if type(v) == "string" then
      return
    end

    if v.gvk then
      local short_name = ""
      if type(v.short_names) == "table" then
        short_name = table.concat(v.short_names, ", ")
      end

      table.insert(data, {
        name = v.plural,
        shortnames = short_name,
        apiversion = v.api_version,
        kind = v.gvk and v.gvk.k or "",
        namespaced = v.namespaced,
      })
    end
  end
  return data
end

return M
