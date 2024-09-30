local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local event_handler = require("kubectl.actions.eventhandler").handler

local M = {
  handle = nil,
  events_handle = nil,
}

local function process_event(builder, event_string)
  local ok, event = pcall(vim.json.decode, event_string, { luanil = { object = true, array = true } })

  if not ok then
    vim.print("parsing error: ", event)
  end

  if not ok or not event or not event.object or not event.object.metadata then
    return
  end
  local event_name = event.object.metadata.name

  local function handle_events(action)
    -- If the event is an event and we are not in events resource,
    -- we assign the involvedObject as event name so the eventhandler can react to those changes
    if event.object.kind == "Event" and builder.resource ~= "events" then
      if event.object.involvedObject and event.object.involvedObject.name then
        event.object.metadata.name = event.object.involvedObject.name
      end
    else
      action()
    end
  end

  -- TODO: prettify this code
  if builder.data.kind == "Table" then
    local target = builder.data
    if event.type == "ADDED" then
      handle_events(function()
        table.insert(target, event.object)
        table.insert(target.rows, { object = event.object, cells = target.rows[1].cells })
      end)
    elseif event.type == "DELETED" then
      for index, row in ipairs(target.rows) do
        if row.object.metadata.name == event_name then
          table.remove(target.rows, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      handle_events(function()
        for index, row in ipairs(target.rows) do
          if row.object.metadata.name == event_name then
            target.rows[index].object = event.object
            break
          end
        end
      end)
    end
  else
    local target = builder.data.items
    if event.type == "ADDED" then
      handle_events(function()
        table.insert(target, event.object)
      end)
    elseif event.type == "DELETED" then
      for index, item in ipairs(target) do
        if item.metadata.name == event_name then
          table.remove(target, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      handle_events(function()
        for index, item in ipairs(target) do
          if item.metadata.name == event_name then
            target[index] = event.object
            break
          end
        end
      end)
    end
  end

  event_handler:emit(event.type, event)
end

local function on_err(err, data)
  vim.schedule(function()
    vim.notify(
      string.format("Error occurred while watching %s %s, refresh view to fix", err or "", data or ""),
      vim.log.levels.ERROR
    )
  end)
end

local function on_stdout(result)
  process_event(M.builder, result)
end

local function on_exit() end

function M.start(builder)
  if not builder.data or not builder.data.metadata then
    return
  end
  if M.handle or M.events_handle then
    M.stop()
  end

  local args = { "-N", "--keepalive-time", "60", "-X", "GET", "-sS", "-H", "Content-Type: application/json" }

  local event_cmd = { state.getProxyUrl() .. "/api/v1/events?pretty=false&watch=true" }
  for _, arg in ipairs(args) do
    table.insert(event_cmd, arg)
  end

  for index, value in ipairs(builder.args) do
    if index == #builder.args then
      value = value .. "&watch=true&resourceVersion=" .. (builder.data.metadata.resourceVersion or "0")
      table.insert(args, value)
    end
  end

  M.handle = commands.shell_uv_async(builder.cmd, args, on_exit, on_stdout, on_err)
  M.events_handle = commands.shell_uv_async("curl", event_cmd, on_exit, on_stdout, on_err)

  M.builder = builder
  return M.handle
end

function M.stop()
  if M.handle and not M.handle:is_closing() then
    M.handle:kill(2)
  end

  if M.events_handle and not M.events_handle:is_closing() then
    M.events_handle:kill(2)
  end
  M.event_queue = ""
end

return M
