local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local string_utils = require("kubectl.utils.string")

local M = {}

---@param port_forwards {pid: string, type: string, resource: string, port: string} @Array of port forwards
---@param async boolean @Indicates whether the function should run asynchronously
---@param kind "pods"|"svc"|"all" @What types we want to retrieve
---@return table[] @Returns the modified array of port forwards
function M.getPortForwards(port_forwards, async, kind)
  if vim.fn.has("win32") == 1 then
    return port_forwards
  end

  local function parse(data)
    if not data then
      return
    end

    for _, line in ipairs(vim.split(data, "\n")) do
      local pid = string_utils.trim(line):match("^(%d+)")
      local resource_type = line:match("%s(pods)/") or line:match("%s(svc)/")

      local resource, port
      if kind == "pods" then
        resource, port = line:match("pods/([^%s]+)%s+(%d+:%d+)$")
      elseif kind == "svc" then
        resource, port = line:match("svc/([^%s]+)%s+(%d+:%d+)$")
      elseif kind == "all" then
        resource, port = line:match("/([^%s]+)%s+(%d+:%d+)$")
      end

      if resource and port then
        table.insert(port_forwards, { pid = pid, type = resource_type, resource = resource, port = port })
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

function M.setPortForwards(marks, data, port_forwards)
  for _, pf in ipairs(port_forwards) do
    if not pf.resource then
      return
    end
    for row, line in ipairs(data) do
      local col = line:find(pf.resource, 1, true)

      if col then
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

return M
