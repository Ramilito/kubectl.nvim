local uv = vim.loop
local timeme = require("kubectl.utils.timeme")

local M = {}
M.handle = {}
M.pid = -1
M.stdout = {}

-- Function to handle stdout data
local function handle_stdout(err, data, callback)
  timeme.stop()
  if err then
    print("Error reading stdout:", err)
    return
  end
  if data then
    callback(data)
  end
end

-- Function to handle process exit
local function handle_exit(code, signal, stdout, stderr)
  print("kubectl proxy exited with code", code, "and signal", signal)
  stdout:close()
  stderr:close()
end

-- Function to stop the kubectl proxy process
function M.stop_kubectl_proxy()
  return function()
    if M.handle and not M.handle:is_closing() then
      uv.kill(M.pid, function()
        print("process closed", M.handle, M.pid)
      end)
    end
  end
end

-- Function to start the kubectl proxy process
function M.startProxy(callback)
  timeme.start()
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  -- Spawn the kubectl proxy process
  M.handle, M.pid = uv.spawn(
    "kubectl",
    {
      args = { "proxy", "--port=8080" },
      stdio = { nil, stdout, stderr },
    },
    vim.schedule_wrap(function(code, signal)
      handle_exit(code, signal, stdout, stderr)
    end)
  )

  -- Check if the process failed to start
  if not M.handle then
    print("Failed to start kubectl proxy")
    return nil
  end

  -- Start reading stdout
  uv.read_start(
    stdout,
    vim.schedule_wrap(function(err, data)
      handle_stdout(err, data, callback)
    end)
  )

  -- Set up an autocommand to stop the kubectl proxy when Neovim exits
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = M.stop_kubectl_proxy(),
  })

  -- Return the process handle for reference
  return M.handle
end

return M
