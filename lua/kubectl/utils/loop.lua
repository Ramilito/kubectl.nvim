local config = require("kubectl.config")
local M = {}

local timers = {}

--- Start a loop for a specific buffer
---@param buf number
---@param callback fun(is_cancelled: fun(): boolean)
---@param opts? { interval: number }: The arguments for the loop.
function M.start_loop_for_buffer(buf, callback, opts)
  if timers[buf] then
    return
  end
  opts = opts or {}

  local interval = opts.interval or config.options.auto_refresh.interval
  local timer = vim.uv.new_timer()
  timers[buf] = { running = false, timer = nil }

  local function is_cancelled()
    return timers[buf] == nil
  end

  timer:start(0, interval, function()
    if not timers[buf] or not timers[buf].running then
      timers[buf].running = true

      vim.schedule(function()
        callback(is_cancelled)
      end)
    end
  end)

  timers[buf].timer = timer

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    buffer = buf,
    callback = function()
      M.start_loop_for_buffer(buf, callback, opts)
    end,
  })

  vim.api.nvim_create_autocmd({ "QuitPre", "BufHidden", "BufUnload", "BufDelete" }, {
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
  if timers[buf] then
    local timer = timers[buf].timer
    if timer then
      timer:stop()
      timer:close()
      timers[buf] = nil
    end
  end
end

function M.set_running(buf, running)
  if timers[buf] then
    timers[buf].running = running
  end
end

function M.stop_all()
  for key, _ in pairs(timers) do
    M.stop_loop(key)
  end
end

--- Check if the loop is running
---@return boolean
function M.is_running(buf)
  return timers[buf] and timers[buf].timer ~= nil
end

return M
