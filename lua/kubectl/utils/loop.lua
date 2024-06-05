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

  -- Store the timer in the table
  timers[buf] = timer

  -- Create an autocommand to stop the timer when the buffer is left
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    callback = function()
      M.stop_loop_for_buffer(buf)
    end,
  })
end

-- Stop the loop for a specific buffer
function M.stop_loop_for_buffer(buf)
  local timer = timers[buf]
  if timer then
    timer:stop()
    timer:close()
    timers[buf] = nil
  end
end

-- Start the loop for the current buffer
function M.start_loop(callback)
  local current_buf = vim.api.nvim_get_current_buf()
  start_loop_for_buffer(current_buf, callback)
end

-- Stop the loop for the current buffer
function M.stop_loop()
  local current_buf = vim.api.nvim_get_current_buf()
  M.stop_loop_for_buffer(current_buf)
end

-- Check if the loop is running for a specific buffer
function M.is_running_for_buffer(buf)
  return timers[buf] ~= nil
end

-- Check if the loop is running for the current buffer
function M.is_running()
  local current_buf = vim.api.nvim_get_current_buf()
  return M.is_running_for_buffer(current_buf)
end

-- Setup function to initialize autocommands
function M.setup()
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
      M.start_loop()
    end,
  })
end

return M
