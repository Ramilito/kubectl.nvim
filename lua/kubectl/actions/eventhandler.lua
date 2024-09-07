local EventHandler = {}
EventHandler.__index = EventHandler

function EventHandler:new()
  local instance = {
    listeners = {},
  }
  setmetatable(instance, self)
  return instance
end

local handler_instance = EventHandler:new()

function EventHandler:on(event, buf_nr, callback)
  if not handler_instance.listeners[event] then
    handler_instance.listeners[event] = {}
  end

  handler_instance.listeners[event][buf_nr] = callback

  vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
    buffer = buf_nr,
    callback = function()
      EventHandler:off(event, buf_nr)
    end,
  })
end

function EventHandler:off(event, buf_nr)
  if not handler_instance.listeners[event] then
    return
  end
  handler_instance.listeners[event][buf_nr] = nil
end

function EventHandler:emit(event, ...)
  if not handler_instance.listeners[event] then
    return
  end
  for _, callback in pairs(handler_instance.listeners[event]) do
    callback(...)
  end
end

return {
  handler = handler_instance,
}
