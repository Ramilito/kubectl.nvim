local hl = require("kubectl.actions.highlight")

local M = {}

function M.getPFRows(type)
  local client = require("kubectl.client")
  local pfs = client.portforward_list()
  local data = {}
  for _, value in pairs(pfs) do
    local item = {
      id = { value = value.id, symbol = hl.symbols.gray },
      type = { value = value.type, symbol = hl.symbols.info },
      name = { value = value.name, symbol = hl.symbols.success },
      ns = { value = value.namespace, symbol = hl.symbols.info },
      port = { value = value.local_port .. ":" .. value.remote_port, symbol = hl.symbols.pending },
    }
    if not type then
      table.insert(data, item)
    elseif type == value.type then
      table.insert(data, item)
    end
  end
  return data
end

function M.setPortForwards(marks, data, port_forwards)
  if not port_forwards or not data then
    return
  end

  for _, pf in ipairs(port_forwards) do
    if not pf.name or not pf.ns then
      return
    end

    for row, line in ipairs(data) do
      local col = line:find(pf.name.value, 1, true)
      local ns = line:find(pf.ns.value, 1, true)
      if col and ns then
        local mark = {
          row = row - 1,
          start_col = col + #pf.name.value - 1,
          end_col = col + #pf.name.value - 1 + 3,
          virt_text = { { " ⇄ ", hl.symbols.success } },
          virt_text_pos = "overlay",
        }
        table.insert(marks, mark)
      end
    end
  end
  return marks
end

return M
