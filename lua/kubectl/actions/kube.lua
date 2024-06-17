local uv = vim.loop
local timeme = require("kubectl.utils.timeme")

local M = {}
M.handle = {}
M.pid = -1

function M.stop_kubectl_proxy()
  return function()
    if M.handle and not M.handle:is_closing() then
      uv.kill(M.pid, function()
        print("process closed", M.handle, M.pid)
      end)
    end
  end
end

function M.startProxy(callback)
  timeme.start()
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  M.handle, M.pid = uv.spawn(
    "kubectl",
    {
      args = { "proxy", "--port=8080" },
      stdio = { nil, stdout, stderr },
    },
    vim.schedule_wrap(function(code, signal)
      print("kubectl proxy exited with code", code, "and signal", signal)
      stdout:close()
      stderr:close()
    end)
  )

  if not M.handle then
    print("Failed to start kubectl proxy")
    return nil
  end

  uv.read_start(
    stdout,
    vim.schedule_wrap(function(err, data)
      timeme.stop()
      if err then
        print("Error reading stdout:", err)
        return
      end
      if data then
        callback(data)
      end
    end)
  )

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = M.stop_kubectl_proxy(),
  })

  return M.handle
end

return M
