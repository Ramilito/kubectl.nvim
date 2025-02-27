local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local event_handler = require("kubectl.actions.eventhandler").handler

---@class Informer
---@field handle any Process handle for the main informer
---@field events_handle any Process handle for the events informer
---@field builder any Builder instance containing resource information
local M = {
  events_handle = nil,
  builders = {},
}

---Process an event from the Kubernetes watch stream
---@param builder table The builder instance
---@param event_string string JSON string containing the event data
---@return boolean success Whether the event was processed successfully
local function process_event(builder, event_string)
  if not builder then
    return false
  end
  local ok, event = pcall(vim.json.decode, event_string, { luanil = { object = true, array = true } })

  if not ok or not event or not event.object or not event.object.metadata then
    return false
  end

  local event_name = event.object.metadata.name

  local function handle_events(action)
    if event.object.kind == "Event" and builder.resource ~= "events" then
      if event.object.involvedObject and event.object.involvedObject.name then
        event.object.metadata.name = event.object.involvedObject.name
      end
    else
      action()
    end
  end

  local function process_event_target(target, is_table)
    if event.type == "ADDED" then
      handle_events(function()
        table.insert(target, event.object)
        if is_table then
          table.insert(target.rows, { object = event.object, cells = target.rows[1].cells })
        end
      end)
    elseif event.type == "DELETED" then
      for index, item in ipairs(is_table and target.rows or target) do
        if (is_table and item.object.metadata.name or item.metadata.name) == event_name then
          for selection_index, selection in ipairs(state.selections) do
            if item.metadata and selection.name == item.metadata.name then
              table.remove(state.selections, selection_index)
            end
          end
          table.remove(is_table and target.rows or target, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      handle_events(function()
        for index, item in ipairs(is_table and target.rows or target) do
          if item.object and item.object.metadata or item.metadata then
            if (is_table and item.object.metadata.name or item.metadata.name) == event_name then
              if is_table then
                target.rows[index].object = event.object
              else
                target[index] = event.object
              end
              break
            end
          end
        end
      end)
    end
  end

  if builder.data.kind == "Table" then
    process_event_target(builder.data, true)
  else
    process_event_target(builder.data.items, false)
  end

  event_handler:emit(event.type, event)
  return true
end

---Execute a shell command asynchronously using libuv
---@param cmd string The command to execute
---@param args table List of command arguments
---@return userdata handle Process handle
local function shell_uv_async(cmd, args, buf)
  local result = ""
  local command = commands.configure_command(cmd, {}, args)
  local handle
  ---@diagnostic disable-next-line: undefined-field
  local stdout = vim.loop.new_pipe(false)
  ---@diagnostic disable-next-line: undefined-field
  local stderr = vim.loop.new_pipe(false)

  ---@diagnostic disable-next-line: undefined-field
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
        if process_event(M.builders[buf], json_str) then
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

---Start the informer for a given resource
---@param builder table The builder instance containing resource information
---@return userdata|nil handle Process handle for the informer
function M.start(builder)
  if not builder.data or not builder.data.metadata then
    return
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

  M.builders[builder.buf_nr] = builder
  M.start_events(event_cmd)
  M.builders[builder.buf_nr].handle = shell_uv_async(builder.cmd, args, builder.buf_nr)

  vim.schedule(function()
    vim.api.nvim_create_autocmd({ "QuitPre", "BufHidden", "BufUnload", "BufDelete" }, {
      buffer = builder.buf_nr,
      callback = function(ev)
        if ev.event == "QuitPre" then
          M.stop_events()
        end
        M.stop(ev.buf)
      end,
    })
  end)
end

function M.start_events(cmd)
  if not M.events_handle then
    M.events_handle = shell_uv_async("curl", cmd)
  end
end

function M.stop_events()
  if M.events_handle and not M.events_handle:is_closing() then
    M.events_handle:kill(2)
  end
end

function M.stop(buf)
  if M.builders[buf] and M.builders[buf].handle and not M.builders[buf].handle:is_closing() then
    M.builders[buf].handle:kill(2)
  end
  M.builders[buf] = nil
end

return M
