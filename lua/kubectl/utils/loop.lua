local config = require("kubectl.config")
local M = {}

local timers = {}

--- Check if a float that should pause refresh is open
---@return boolean
local function has_active_float()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_config = vim.api.nvim_win_get_config(win)
    if win_config.relative ~= "" then
      -- LSP float (hover/diagnostic) has w:lsp_floating_bufnr set by Neovim
      local ok = pcall(vim.api.nvim_win_get_var, win, "lsp_floating_bufnr")
      if ok then
        return true
      end
    end
  end
  return false
end

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
        -- Skip refresh if LSP hover or diagnostic float is open
        if has_active_float() then
          timers[buf].running = false
          return
        end
        callback(is_cancelled)
      end)
    end
  end)

  timers[buf].timer = timer

  local group = vim.api.nvim_create_augroup("Kubectl", { clear = false })
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    buffer = buf,
    group = group,
    callback = function()
      M.start_loop_for_buffer(buf, callback, opts)
    end,
  })

  vim.api.nvim_create_autocmd({ "QuitPre", "BufHidden", "BufUnload", "BufDelete" }, {
    buffer = buf,
    group = group,
    callback = function()
      M.stop_loop(buf)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "K8sContextChanged",
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        M.start_loop_for_buffer(buf, callback, opts)
      end
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
