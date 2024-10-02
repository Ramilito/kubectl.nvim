local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local time = require("kubectl.utils.time")

local M = {
  proxy_state = {
    running = false,
    text = "pending",
    timestamp = 0,
  },
  handle = {},
  pid = -1,
  hc_handle = {},
  hc_pid = -1,
}

function M.stop_kubectl_proxy()
  return function()
    if M.handle and not M.handle:is_closing() then
      M.handle:kill(2)
    end
  end
end

function M.api_server_healthcheck()
  if M.handle and not M.handle:is_closing() then
    vim.system({ "curl", "-s", state.getProxyUrl() .. "/livez" }, {
      text = true,
      timeout = 5000,
      stderr = function(_, data)
        vim.schedule(function()
          if data then
            M.proxy_state.running = false
            M.proxy_state.text = "failed"
          end
        end)
      end,
      stdout = function(_, data)
        vim.schedule(function()
          if data then
            local status = data:match("ok")
            if status then
              M.proxy_state.running = true
              M.proxy_state.text = "running"
              M.proxy_state.timestamp = time.currentTime()
            else
              M.proxy_state.running = false
              M.proxy_state.text = "failed"
            end
          end
        end)
      end,
    })
  else
    M.proxy_state.running = false
    M.proxy_state.text = "not running"
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
    clear_env = true,
    env = command.env,
    stdin = false,
    stderr = function(_, data)
      vim.schedule(function()
        if data then
          M.proxy_state.running = false
          M.proxy_state.text = "failed"
        end
      end)
    end,
    stdout = on_stdout,
    detach = false,
  }, M.stop_kubectl_proxy())

  M.handle = handle

  -- Heartbeat timer
  local timer = vim.uv.new_timer()
  timer:start(0, 5000, M.api_server_healthcheck)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      handle:kill(2)
    end,
  })
end

return M
