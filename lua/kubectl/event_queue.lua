local client = require("kubectl.client")

local M = {
  _callbacks = {},   -- name -> function(payload)
  _timer = nil,
}

-- Register a callback. Accept a function or a code string that evaluates to a function.
function M.register(name, fn_or_code)
  local fn = fn_or_code
  if type(fn_or_code) == "string" then
    local ok, chunk = pcall(load, "return " .. fn_or_code)
    if not ok then error("invalid callback code: " .. chunk) end
    fn = chunk()
  end
  if type(fn) ~= "function" then
    error("callback must be a function or a code string that returns a function")
  end
  M._callbacks[name] = fn
end

function M.unregister(name)
  M._callbacks[name] = nil
end

-- Start the polling channel (default 50ms). Small, safe, and on the main loop.
function M.start(interval_ms)
  client.setup()
  local uv = vim.uv or vim.loop
  M._timer = uv.new_timer()
  M._timer:start(0, interval_ms or 50, vim.schedule_wrap(function()
    local batch = client.pop_all()
    for _, ev in ipairs(batch) do
      local cb = M._callbacks[ev.name]
      if cb then
        cb(ev.payload)  -- run your code for this channel
      end
      -- Optional: also broadcast as a User autocmd if you like
      -- vim.api.nvim_exec_autocmds("User", { pattern = "KubectlEvent", data = ev })
    end
  end))
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

-- Quick smoke test:
function M.demo()
  M.register("pods", function(payload)
    local ok, obj = pcall(vim.json.decode, payload)
    vim.notify(("pods -> %s"):format(ok and vim.inspect(obj) or payload))
  end)
  client.emit("pods", '{"kind":"Pod","action":"MODIFIED"}')
end

return M
