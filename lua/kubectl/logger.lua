local cfg = require("kubectl.config")
local str_u = require("kubectl.utils.string")

local default_notify_opts = {
  title = "kubectl",
}

local log = {}

--- Adds a log entry using Plenary.log
---@param msg any
---@param level string [same as vim.log.log_levels]
function log:add_entry(msg, level)
  if not self.__notify_fmt then
    self.__notify_fmt = function(m)
      return string.format(cfg.logging.notify_format, m)
    end
  end

  if cfg.logging.level == "off" then
    return
  end

  if self.__handle then
    local fmt_msg = self.__handle[level]
    ---@cast fmt_msg fun(msg: string)
    fmt_msg(msg)
    return
  end

  local default_opts = {
    plugin = "kubectl",
    level = cfg.logging.level or "warn",
    use_console = false,
    info_level = 4,
  }

  local has_plenary, plenary_log = pcall(require, "plenary.log")
  if not has_plenary then
    return
  end

  local handle = plenary_log.new(default_opts)
  local fmt_msg = handle[level]
  ---@cast fmt_msg fun(msg: string)
  fmt_msg(msg)
  self.__handle = handle
end

--- Retrieves the path of the logfile
---@return string path path of the logfile
function log:get_path()
  return str_u.path_join(vim.fn.stdpath("cache") --[[@as string]], "kubectl.log")
end

---Add a log entry at TRACE level
---@param msg any
function log:trace(msg)
  self:add_entry(msg, "trace")
end

---Add a log entry at DEBUG level
---@param msg any
function log:debug(msg)
  self:add_entry(msg, "debug")
end

---Add a log entry at INFO level
---@param msg any
function log:info(msg)
  self:add_entry(msg, "info")
end

---Add a log entry at WARN level
---@param msg any
function log:warn(msg)
  self:add_entry(msg, "warn")
  vim.notify(self.__notify_fmt(msg), vim.log.levels.WARN, default_notify_opts)
end

---Add a log entry at ERROR level
---@param msg any
function log:error(msg)
  self:add_entry(msg, "error")
  vim.notify(self.__notify_fmt(msg), vim.log.levels.ERROR, default_notify_opts)
end

setmetatable({}, log)
return log
