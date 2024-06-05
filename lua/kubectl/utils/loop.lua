local M = {}

local timers = {}

function M.start_loop(callback)
  local buf = vim.api.nvim_get_current_buf()
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
      callback(buf)
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

function M.stop_loop()
  local buf = vim.api.nvim_get_current_buf()
  local timer = timers[buf]
  if timer then
    timer:stop()
    timer:close()
    timers[buf] = nil
  end
end

function M.is_running()
  local current_buf = vim.api.nvim_get_current_buf()
  return timers[current_buf] ~= nil
end

return M
