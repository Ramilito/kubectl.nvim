local config = require("kubectl.config")
local M = {}

local timers = {}

local function start_loop_for_buffer(buf, callback)
  if timers[buf] then
    return
  end

  local timer = vim.loop.new_timer()

  timer:start(
    0,
    3000,
    vim.schedule_wrap(function()
      if vim.api.nvim_get_current_buf() ~= buf then
        return
      end
      callback()
    end)
  )

  timers[buf] = timer

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    callback = function()
      M.stop_loop_for_buffer(buf)
    end,
  })
end

function M.stop_loop_for_buffer(buf)
  local timer = timers[buf]
  if timer then
    timer:stop()
    timer:close()
    timers[buf] = nil
  end
end

function M.start_loop(callback)
  local current_buf = vim.api.nvim_get_current_buf()
  start_loop_for_buffer(current_buf, callback)
end

function M.stop_loop()
  local current_buf = vim.api.nvim_get_current_buf()
  M.stop_loop_for_buffer(current_buf)
end

function M.is_running_for_buffer(buf)
  return timers[buf] ~= nil
end

function M.is_running()
  local current_buf = vim.api.nvim_get_current_buf()
  return M.is_running_for_buffer(current_buf)
end

function M.setup()
  if config.options.auto_refresh then
    vim.api.nvim_create_autocmd("BufEnter", {
      callback = function()
        vim.schedule(function()
          M.start_loop()
        end)
      end,
    })
  end
end

return M
