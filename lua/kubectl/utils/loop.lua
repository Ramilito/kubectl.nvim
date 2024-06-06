local config = require("kubectl.config")
local M = {}

local timers = {}

function M.start_loop_for_buffer(buf, callback)
  if timers[buf] then
    return
  end

  local running = false
  local timer = vim.uv.new_timer()

  timer:start(0, 3000, function()
    if running then
      return
    end
    running = true
    vim.schedule(function()
      if vim.api.nvim_get_current_buf() ~= buf then
        return
      end

      callback()
      running = false
    end)
  end)

  timers[buf] = timer

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    buffer = buf,
    callback = function()
      M.start_loop_for_buffer(buf, callback)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
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
  if config.options.auto_refresh then
    local current_buf = vim.api.nvim_get_current_buf()
    M.start_loop_for_buffer(current_buf, callback)
  end
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

return M
