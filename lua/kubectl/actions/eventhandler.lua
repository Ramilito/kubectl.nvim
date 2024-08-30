local EventHandler = {}
EventHandler.__index = EventHandler

function EventHandler:new()
  local instance = {
    listeners = {},
  }
  setmetatable(instance, self)
  return instance
end

function EventHandler:on(event, id, callback)
  if not self.listeners[event] then
    self.listeners[event] = {}
  end

  self.listeners[event][id] = callback
end

function EventHandler:off(event, id)
  if not self.listeners[event] then
    return
  end
  self.listeners[event][id] = nil
end

function EventHandler:emit(event, ...)
  if not self.listeners[event] then
    return
  end
  for _, callback in pairs(self.listeners[event]) do
    callback(...)
  end
end

local handler_instance = EventHandler:new()

return {
  handler = handler_instance,
}
