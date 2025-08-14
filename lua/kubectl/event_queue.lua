local client = require("kubectl.client")

local M = {
  _callbacks = {},
  _timer = nil,
}

function M.register(name, buf_nr, fn_or_code)
  local fn = fn_or_code
  if type(fn_or_code) == "string" then
    local ok, chunk = pcall(load, "return " .. fn_or_code)
    if not ok then
      error("invalid callback code: " .. chunk)
    end
    fn = chunk()
  end
  if type(fn) ~= "function" then
    error("callback must be a function or a code string that returns a function")
  end
  M._callbacks[name] = fn

  vim.api.nvim_create_autocmd({ "QuitPre", "BufHidden", "BufUnload", "BufDelete" }, {
    buffer = buf_nr,
    callback = function()
      M.unregister(name)
    end,
  })
end

function M.unregister(name)
  M._callbacks[name] = nil
end

function M.start(interval_ms)
  client.setup_queue()
  local uv = vim.uv or vim.loop
  M._timer = uv.new_timer()
  M._timer:start(
    0,
    interval_ms or 50,
    vim.schedule_wrap(function()
      local batch = client.pop_queue()
      for _, ev in ipairs(batch) do
        local cb = M._callbacks[ev.name]
        if cb then
          cb(ev.payload)
        end
        -- TODO: also broadcast as a User autocmd
        -- vim.api.nvim_exec_autocmds("User", { pattern = "KubectlEvent", data = ev })
      end
    end)
  )
end

function M.stop()
  if M._timer then
    pcall(function()
      M._timer:stop()
      M._timer:close()
    end)
    M._timer = nil
  end
end

return M
