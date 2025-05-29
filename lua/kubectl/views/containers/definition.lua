local M = {}

function M.processRow(row)
  local data = {}

  if not row or #row == 0 then
    return data
  end

  for _, c in ipairs(row[1].containers) do
    table.insert(data, {
      name = c.name,
      image = c.image,
      ready = c.ready,
      state = c.state,
      type = c.type,
      restarts = c.restarts,
      ports = c.ports,
      cpu = c.cpu,
      mem = c.mem,
      ["%cpu/r"] = c["%cpu/r"],
      ["%cpu/l"] = c["%cpu/l"],
      ["%mem/r"] = c["%mem/r"],
      ["%mem/l"] = c["%mem/l"],
      age = c.age,
    })
  end
  return data
end

return M
