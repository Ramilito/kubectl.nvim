local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {
  headers = {
    "NAME",
  },
  namespaced = false,
}

function M.processRow(rows)
  local data = {}
  if not rows then
    return data
  end

  if rows.rows and #rows.rows > 0 then
    for _, row in pairs(rows.rows) do
      local resource_vals = row.cells
      local resource = {}
      local namespace = row.object.metadata.namespace
      if namespace then
        resource.namespace = namespace
      end
      for i, val in pairs(resource_vals) do
        local res_key = string.lower(rows.columnDefinitions[i].name)
        local is_time = time.since(val)
        -- if the value parsed as time, then it's age/created at column
        if is_time then
          resource[res_key] = is_time
        else
          resource[res_key] = { value = val or "", symbol = events.ColorStatus(val) }
        end
      end

      table.insert(data, resource)
    end
  end
  return data
end

function M.getHeaders(rows)
  if not rows then
    return M.headers
  end

  local headers
  if rows.columnDefinitions then
    headers = {}
    if M.namespaced then
      table.insert(headers, 1, "NAMESPACE")
    end

    for _, col in pairs(rows.columnDefinitions) do
      local col_name = string.upper(col.name)
      if not headers[col_name] then
        table.insert(headers, string.upper(col_name))
      end
    end
  end
  M.headers = headers
  return headers
end

return M
