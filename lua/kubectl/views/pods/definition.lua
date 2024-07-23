local commands = require("kubectl.actions.commands")
local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local M = {}

local function getReady(row)
  local status = { symbol = "", value = "" }
  local readyCount = 0
  local containers = 0
  if row.status.containerStatuses then
    for _, value in ipairs(row.status.containerStatuses) do
      containers = containers + 1
      if value.ready then
        readyCount = readyCount + 1
      end
    end
  end
  if readyCount == containers then
    status.symbol = hl.symbols.note
  else
    status.symbol = hl.symbols.deprecated
  end
  status.value = readyCount .. "/" .. containers
  return status
end

local function getRestarts(containerStatuses, currentTime)
  if not containerStatuses then
    return 0
  end

  local restartCount = 0
  local lastState

  for _, value in ipairs(containerStatuses) do
    if value.lastState and value.lastState.terminated then
      lastState = time.since(value.lastState.terminated.finishedAt, false, currentTime)
    end
    restartCount = restartCount + value.restartCount
  end
  if lastState then
    return string.format("%d (%s ago)", restartCount, lastState.value)
  else
    return restartCount
  end
end

local function getPodStatus(phase)
  local status = { symbol = events.ColorStatus(phase), value = phase }
  return status
end

---@param port_forwards table[] @Array of port forwards where each item has `resource` and `port` keys
---@param async boolean @Indicates whether the function should run asynchronously
---@return table[] @Returns the modified array of port forwards
function M.getPortForwards(port_forwards, async)
  if vim.fn.has("win32") == 1 then
    return port_forwards
  end

  local function parse(data)
    for _, line in ipairs(vim.split(data, "\n")) do
      local resource, port = line:match("pods/([^%s]+)%s+(%d+:%d+)")
      if resource and port then
        table.insert(port_forwards, { resource = resource, port = port })
      end
    end
  end

  if async then
    commands.execute_shell_command_async("ps -eo args | grep '[k]ubectl port-forward'", function(_, data)
      if not data then
        return
      end
      parse(data)
    end)
  else
    local data = commands.shell_command("sh", { "-c", "ps -eo args | grep '[k]ubectl port-forward'" })
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

function M.processRow(rows)
  local data = {}
  local currentTime = time.currentTime()
  if rows and rows.items then
    for i = 1, #rows.items do
      local row = rows.items[i]
      data[i] = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = getReady(row),
        status = getPodStatus(row.status.phase),
        restarts = getRestarts(row.status.containerStatuses, currentTime),
        node = row.spec.nodeName,
        age = time.since(row.metadata.creationTimestamp, true, currentTime),
      }
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "READY",
    "STATUS",
    "RESTARTS",
    "NODE",
    "AGE",
  }

  return headers
end

return M
