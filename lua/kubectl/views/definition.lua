local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")

local M = {}

---@param port_forwards {pid: string, type: string, resource: string, port: string} @Array of port forwards
---@param async boolean @Indicates whether the function should run asynchronously
---@param kind "pods"|"svc"|"all" @What types we want to retrieve
---@return table[] @Returns the modified array of port forwards
function M.getPFData(port_forwards, async, kind)
  if vim.fn.has("win32") == 1 then
    return port_forwards
  end

  local function parse(data)
    if not data then
      return
    end

    for _, line in ipairs(vim.split(data, "\n")) do
      if line == "" then
        return
      end
      line = vim.trim(line)
      local pid = line:match("^(%d+)")
      local resource_type = line:match("%s(pods)/") or line:match("%s(svc)/")

      local resource, ns
      local port = line:match("(%d+:%d+)")
      ns = line:match("%-n%s+(%S+)")
      if kind == "pods" then
        resource = line:match("pods/([^%s]+)")
      elseif kind == "svc" then
        resource = line:match("svc/([^%s]+)")
      elseif kind == "all" then
        resource = line:match("[ps][ov][cd]s?/([%w%-]+)")
      end

      if resource and port then
        table.insert(port_forwards, { pid = pid, type = resource_type, resource = resource, ns = ns, port = port })
      end
    end
  end

  local args = "ps -eo pid,args | grep '[k]ubectl port-forward'"
  if async then
    commands.shell_command_async("sh", { "-c", args }, function(data)
      parse(data)
    end)
  else
    local data = commands.shell_command("sh", { "-c", args })
    parse(data)
  end

  return port_forwards
end

function M.getPFRows(pfs)
  local data = {}
  for _, value in ipairs(pfs) do
    table.insert(data, {
      pid = { value = value.pid, symbol = hl.symbols.gray },
      type = { value = value.type, symbol = hl.symbols.info },
      resource = { value = value.resource, symbol = hl.symbols.success },
      ns = { value.ns, symbol = hl.symbols.info },
      port = { value = value.port, symbol = hl.symbols.pending },
    })
  end
  return data
end

function M.setPortForwards(marks, data, port_forwards)
  if not port_forwards then
    return
  end
  for _, pf in ipairs(port_forwards) do
    if not pf.resource or not pf.ns then
      return
    end
    for row, line in ipairs(data) do
      local col = line:find(pf.resource, 1, true)
      local ns = line:find(pf.ns, 1, true)
      if col and ns then
        local mark = {
          row = row - 1,
          start_col = col + #pf.resource - 1,
          end_col = col + #pf.resource - 1 + 3,
          virt_text = { { " ⇄ ", hl.symbols.success } },
          virt_text_pos = "overlay",
        }
        table.insert(marks, #marks, mark)
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
