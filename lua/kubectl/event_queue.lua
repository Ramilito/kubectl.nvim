local client = require("kubectl.client")

local M = {
  callbacks = {},
}

function M.register(name, buf_nr, fn)
  if type(fn) ~= "function" then
    error("callback must be a function or a code string that returns a function")
  end
  M.callbacks[name] = fn

  local group = vim.api.nvim_create_augroup("Kubectl", { clear = false })
  vim.api.nvim_create_autocmd({ "QuitPre", "BufHidden", "BufUnload", "BufDelete" }, {
    buffer = buf_nr,
    group = group,
    callback = function()
      M.unregister(name)
    end,
  })
end

function M.unregister(name)
  M.callbacks[name] = nil
end

function M.start(interval_ms)
  client.setup_queue()
  M.timer = vim.uv.new_timer()
  M.timer:start(
    0,
    interval_ms or 50,
    vim.schedule_wrap(function()
      local batch = client.pop_queue()
      for _, ev in ipairs(batch) do
        local cb = M.callbacks[ev.name]
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
  if M.timer then
    pcall(function()
      M.timer:stop()
      M.timer:close()
    end)
    M.timer = nil
  end
end

return M
