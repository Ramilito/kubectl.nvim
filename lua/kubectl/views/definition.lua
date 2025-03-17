local client = require("kubectl.client")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")

local M = {}

function M.getPFRows()
  local pfs = client.portforward_list()
  local data = {}
  for _, value in pairs(pfs) do
    table.insert(data, {
      id = { value = value.id, symbol = hl.symbols.gray },
      type = { value = value.type, symbol = hl.symbols.info },
      name = { value = value.name, symbol = hl.symbols.success },
      ns = { value = value.namespace, symbol = hl.symbols.info },
      port = { value = value.local_port .. ":" .. value.remote_port, symbol = hl.symbols.pending },
    })
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

function M.on_prompt_input(input)
  if input == "" then
    return
  end
  local history = state.alias_history
  local history_size = config.options.alias.max_history

  local result = {}
  local exists = false
  for i = 1, math.min(history_size, #history) do
    if history[i] ~= input then
      table.insert(result, history[i])
    else
      table.insert(result, 1, input)
      exists = true
    end
  end

  if not exists and input ~= "" then
    table.insert(result, 1, input)
    if #result > history_size then
      table.remove(result, #result)
    end
  end

  state.alias_history = result

  local parsed_input = string.lower(vim.trim(input))
  local view = require("kubectl.views")
  view.view_or_fallback(parsed_input)
end

function M.merge_views(cached_resources, views_table)
  -- merge the data from the viewsTable with the data from the cached_api_resources
  for _, views in pairs(views_table) do
    for _, view in ipairs(views) do
      if not vim.tbl_contains(vim.tbl_keys(cached_resources), view) then
        cached_resources[view] = { name = view }
      end
    end
  end
  return cached_resources
end

return M
