local config = require("kubectl.config")
local M = {}

local timers = {}

--- Start a loop for a specific buffer
---@param buf number
---@param callback fun()
---@param opts? { interval: number }: The arguments for the loop.
function M.start_loop_for_buffer(buf, callback, opts)
  if timers[buf] then
    return
  end
  opts = opts or {}

  local interval = opts.interval or config.options.auto_refresh.interval
  local timer = vim.uv.new_timer()
  local running = false

  timer:start(0, interval, function()
    if not running then
      running = true

      vim.schedule(function()
        callback()

        running = false
      end)
    end
  end)

  timers[buf] = timer

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    buffer = buf,
    callback = function()
      M.start_loop_for_buffer(buf, callback, opts)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufHidden", "BufUnload", "BufDelete" }, {
    buffer = buf,
    callback = function()
      M.stop_loop(buf)
    end,
  })
end

--- Start the loop
---@param callback fun(is_cancelled: fun(): boolean)
function M.start_loop(callback, opts)
  if config.options.auto_refresh.enabled then
    M.start_loop_for_buffer(opts.buf, callback, opts)
  end
end

--- Stop the loop for a specific buffer
---@param buf number: The buffer number.
function M.stop_loop(buf)
  local timer = timers[buf]
  if timer then
    timer:stop()
    timer:close()
    timers[buf] = nil
  end
end

--- Check if the loop is running
---@return boolean
function M.is_running(buf)
  return timers[buf] ~= nil
end

return M
