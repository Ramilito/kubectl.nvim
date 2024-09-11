local commands = require("kubectl.actions.commands")
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

function M.start_kubectl_proxy(callback)
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
  local cmd = "kubectl"
  local command = commands.configure_command(cmd, {}, { "proxy", "--port=0" })

  local handle = vim.system(command.args, {
    clear_env = false,
    env = command.env,
    stdin = false,
    stderr = function(_, data)
      vim.schedule(function()
        if data then
          vim.notify(data, vim.log.levels.ERROR)
        end
      end)
    end,
    stdout = on_stdout,
    detach = false,
  }, M.stop_kubectl_proxy())

  M.handle = handle
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      handle:kill(2)
    end,
  })
end

return M
