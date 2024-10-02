local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local time = require("kubectl.utils.time")

local M = {
  proxy_state = {
    ok = false,
    text = "pending",
    timestamp = 0,
    symbol = hl.symbols.experimental,
  },
  handle = {},
  pid = -1,
  hc_handle = {},
  hc_pid = -1,
}

local function set_proxy_state(state_txt)
  local state_tbl = { text = state_txt }
  if state_txt == "ok" then
    state_tbl.ok = true
    state_tbl.symbol = hl.symbols.success
    state_tbl.timestamp = time.currentTime()
  elseif state_txt == "failed" then
    state_tbl.ok = false
    state_tbl.symbol = hl.symbols.error
  elseif state_txt == "not running" then
    state_tbl.ok = false
    state_tbl.symbol = hl.symbols.error
  end
  M.proxy_state = vim.tbl_extend("force", M.proxy_state, state_tbl)
end

local function api_server_healthcheck()
  if M.handle and not M.handle:is_closing() then
    vim.system({ "curl", "-s", state.getProxyUrl() .. "/livez" }, {
      text = true,
      timeout = 5000,
      stderr = function(_, data)
        if data then
          set_proxy_state("failed")
        end
      end,
      stdout = function(_, data)
        if data then
          local status = data:match("ok")
          if status then
            set_proxy_state("ok")
          else
            set_proxy_state("failed")
          end
        end
      end,
    })
  else
    set_proxy_state("not running")
  end
end

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
    clear_env = true,
    env = command.env,
    stdin = false,
    stderr = function(_, data)
      vim.schedule(function()
        if data then
          set_proxy_state("failed")
        end
      end)
    end,
    stdout = on_stdout,
    detach = false,
  }, M.stop_kubectl_proxy())

  M.handle = handle

  -- Heartbeat timer
  local timer = vim.uv.new_timer()
  timer:start(0, 5000, api_server_healthcheck)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      handle:kill(2)
    end,
  })
end

return M
