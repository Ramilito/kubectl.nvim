local state = require("kubectl.state")

local M = {}
M.handle = {}
M.pid = -1

function M.stop_kubectl_proxy()
  return function()
    if M.handle and not M.handle:is_closing() then
      M.handle:kill(2)
    end
  end
end

function M.startProxy(callback)
  local function on_stdout(err, data)
    if err then
      print("Error reading stdout:", err)
      return
    end
    if data then
      local port = data:match(":(%d+)")
      if port then
        port = tonumber(port)
        if port and port > 0 and port <= 65535 then
          state.setProxyUrl(port)
          callback()
        else
          print("Invalid port number:", port)
        end
      else
        print("No port number found in the output.")
      end
    end
  end

  M.handle = vim.system({ "kubectl", "proxy", "--port=0" }, {
    stdin = false,
    stderr = false,
    stdout = on_stdout,
    detach = false,
  }, M.stop_kubectl_proxy())

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = M.stop_kubectl_proxy(),
  })
end

return M
