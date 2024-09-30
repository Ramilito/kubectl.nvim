local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local event_handler = require("kubectl.actions.eventhandler").handler

local M = {
  handle = nil,
  events_handle = nil,
}

local function process_event(builder, event_string)
  local ok, event = pcall(vim.json.decode, event_string, { luanil = { object = true, array = true } })

  if not ok or not event or not event.object or not event.object.metadata then
    return false
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
  return true
end

local function shell_uv_async(cmd, args)
  local result = ""
  local command = commands.configure_command(cmd, {}, args)
  local handle
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  handle = vim.loop.spawn(command.args[1], {
    args = { unpack(command.args, 2) },
    env = command.env,
    stdio = { nil, stdout, stderr },
    detached = false,
  }, function()
    stdout:close()
    stderr:close()
    -- result = ""
    handle:close()
  end)

  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then
      result = result .. data
      while true do
        local newline_pos = result:find("\n")
        if not newline_pos then
          break
        end

        local json_str = result:sub(1, newline_pos - 1)
        if process_event(M.builder, json_str) then
          result = result:sub(newline_pos + 1)
        else
          break
        end
      end
    end
  end)

  stderr:read_start(function(err, data)
    vim.schedule(function()
      if data then
        vim.notify(
          string.format("Error occurred while watching %s %s, refresh view to fix", err or "", data or ""),
          vim.log.levels.ERROR
        )
      end
    end)
  end)

  return handle
end

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

  M.handle = shell_uv_async(builder.cmd, args)
  M.events_handle = shell_uv_async("curl", event_cmd)

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
end

return M
