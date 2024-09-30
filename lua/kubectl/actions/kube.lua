local commands = require("kubectl.actions.commands")
local log = require("kubectl.log")
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
      log.fmt_error("Error reading stdout: %s", err)
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
          log.fmt_error("Invalid port number: %s", port)
        end
      else
        log.fmt_error("No port number found in the output.")
      end
    end
  end
  local cmd = "kubectl"
  local command = commands.configure_command(cmd, {}, { "proxy", "--port=0" })

  log.fmt_debug("Executing command: %s", command.args)
  local handle = vim.system(command.args, {
    clear_env = true,
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
