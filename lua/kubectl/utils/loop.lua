local M = {}

local timer = nil
local current_buf = nil

function M.start_loop(callback, caller)
  current_buf = vim.api.nvim_get_current_buf()

  if timer then
    M.stop_loop()
  end

  timer = vim.loop.new_timer()

  print("Caller: ", caller)
  timer:start(
    0,
    3000,
    vim.schedule_wrap(function()
      if vim.api.nvim_get_current_buf() ~= current_buf then
        M.stop_loop()
        return
      end
      if callback then
        callback()
      end
    end)
  )

  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = current_buf,
    callback = function()
      M.start_loop(callback)
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = current_buf,
    callback = function()
      M.stop_loop()
    end,
  })
end

function M.stop_loop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

function M.is_running()
  return timer ~= nil
end

return M
