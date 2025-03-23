local M = {}

function M.configure_command(cmd, envs, args)
  local config = require("kubectl.config")
  local result = {
    env = {},
    args = {},
  }

  local current_env = vim.fn.environ()

  if cmd == "kubectl" then
    cmd = config.options.kubectl_cmd.cmd
    local options_args = config.options.kubectl_cmd.args or {}
    local options_env = config.options.kubectl_cmd.env or {}
    local mixer = function(key, value)
      return type(key) == "number" and value or key .. "=" .. value
    end
    vim.list_extend(result.args, vim.iter(options_args):map(mixer):totable())
    vim.list_extend(result.env, vim.iter(options_env):map(mixer):totable())

    local state = require("kubectl.state")
    if state.context["current-context"] then
      table.insert(result.args, "--context")
      table.insert(result.args, state.context["current-context"])
    end
  elseif cmd == "helm" then
    local state = require("kubectl.state")
    if state.context["current-context"] then
      table.insert(result.args, "--kube-context")
      table.insert(result.args, state.context["current-context"])
    end
  end

  table.insert(result.env, "PATH=" .. current_env["PATH"])
  if current_env["HOME"] then
    table.insert(result.env, "HOME=" .. current_env["HOME"])
  end
  if current_env["KUBECONFIG"] then
    table.insert(result.env, "KUBECONFIG=" .. current_env["KUBECONFIG"])
  end
  if current_env["KUBECACHEDIR"] then
    table.insert(result.env, "KUBECACHEDIR=" .. current_env["KUBECACHEDIR"])
  end

  if envs then
    vim.list_extend(result.env, envs)
  end

  for key, value in pairs(result.env) do
    result.env[key] = value:gsub("%$(%w+)", os.getenv)
  end

  if args then
    vim.list_extend(result.args, args)
  end

  for key, value in pairs(result.args) do
    result.args[key] = value:gsub("%$(%w+)", os.getenv)
  end

  -- Add the command itself as the first argument
  table.insert(result.args, 1, cmd)

  return result
end

--- Execute a shell command synchronously
--- @param cmd string The command to execute
--- @param args string[] The arguments for the command
--- @param opts { env: table, on_stdout: function, stdin: string }|nil The arguments for the command
--- @return string The result of the command execution
function M.shell_command(cmd, args, opts)
  opts = opts or {}
  local result = ""
  local error_result = ""
  local command = M.configure_command(cmd, opts.env, args)

  local job = vim.system(command.args, {
    text = true,
    env = command.env,
    clear_env = true,
    stdin = opts.stdin,
    stdout = function(_, data)
      if data then
        result = result .. data
        if opts.on_stdout then
          opts.on_stdout(data)
        end
      end
    end,
    stderr = function(_, data)
      if data then
        error_result = error_result .. data
      end
    end,
  })

  -- Wait for the job to complete
  local exit_code = job:wait()

  if exit_code.code ~= 0 and error_result ~= "" then
    vim.notify(error_result, vim.log.levels.ERROR)
  end

  return result
end

function M.await_shell_command_async(cmds, callback)
  local handles = {}
  local results = {}
  local done_count = 0
  local active_count = 0
  local max_concurrent = 50
  local next_cmd_index = 1 -- Index of the next command to start

  -- Forward declarations of functions
  local start_command
  local on_command_done

  -- Function to start a command
  start_command = function(i)
    local cmd = cmds[i]
    active_count = active_count + 1
    handles[i] = M.run_async(cmd.cmd, cmd.args, function(result)
      on_command_done(i, result)
    end)
  end

  -- Callback to check when all commands are done
  on_command_done = function(i, result)
    results[i] = result
    done_count = done_count + 1
    active_count = active_count - 1 -- Decrement the count of active commands

    -- Start the next command if any are left
    if next_cmd_index <= #cmds then
      start_command(next_cmd_index)
      next_cmd_index = next_cmd_index + 1
    elseif done_count == #cmds then
      -- All commands are complete; call the callback with the results
      if callback then
        callback(results)
      end
    end
  end

  -- Start the initial batch of commands
  while active_count < max_concurrent and next_cmd_index <= #cmds do
    start_command(next_cmd_index)
    next_cmd_index = next_cmd_index + 1
  end

  return handles
end

--- Execute a shell command asynchronously
--- @param cmd string The command to execute
--- @param args string[] The arguments for the command
--- @param on_exit? function The callback function to execute when the command exits (optional)
--- @param on_stdout? function The callback function to execute when there is stdout output (optional)
--- @param on_stderr? function The callback function to execute when there is stderr output (optional)
--- @param opts { env: table, stdin: string, detach: boolean, timeout: number }|nil The arguments for the command
function M.shell_command_async(cmd, args, on_exit, on_stdout, on_stderr, opts)
  opts = opts or { env = {} }
  local result = ""
  local command = M.configure_command(cmd, opts.env, args)
  local handle = vim.system(command.args, {
    text = true,
    env = command.env,
    clear_env = true,
    detach = opts.detach or false,
    stdin = opts.stdin,
    timeout = opts.timeout or nil,
    stdout = function(err, data)
      if err then
        return
      end
      if data then
        result = result .. data
        if on_stdout then
          on_stdout(data)
        end
      end
    end,

    stderr = function(err, data)
      vim.schedule(function()
        if data and on_stderr then
          on_stderr(err, data)
        elseif data then
          vim.notify(data, vim.log.levels.ERROR)
        end
      end)
    end,
  }, function()
    if on_exit then
      on_exit(result)
    end
  end)

  return handle
end

function M.run_async(method_name, args, callback)
  local function after_work_callback(results, err)
    callback(results, err)
  end
  local function work_callback(cpath, method, ...)
    package.cpath = cpath
    local mod = require("kubectl_client")
    local ok, result = pcall(mod[method], ...)
    if not ok then
      return nil, result
    end
    return result, nil
  end

  return vim.uv.new_work(work_callback, after_work_callback):queue(package.cpath, method_name, unpack(args))
end

--- Execute a shell command using io.popen
--- @param cmd string The command to execute
--- @param args string|string[] The arguments for the command
--- @return string result The result of the command execution
function M.execute_shell_command(cmd, args)
  if type(args) == "table" then
    args = table.concat(args, " ")
  end

  local full_command = cmd .. " " .. args
  local handle = io.popen(full_command, "r")
  if handle == nil then
    return "Failed to execute command: " .. cmd
  end
  local result = handle:read("*a")
  handle:close()

  return result
end

--- Execute a command in a terminal
--- NOTE: Don't use this for kubectl calls since this doesn't support clear_env
--- @param cmd string The command to execute
--- @param args string|string[] The arguments for the command
-- luacheck: no max line length
--- @param opts { env: table, stdin: string, on_stdout: string, detach: boolean, timeout: number }|nil The arguments for the command
function M.execute_terminal(cmd, args, opts)
  opts = opts or {}
  local command = M.configure_command(cmd, opts.env, args)

  local envs = {}
  for _, env_var in ipairs(command.env) do
    local key, value = string.match(env_var, "^([^=]+)=(.+)$")
    if key and value then
      envs[key] = value
    else
      print("Invalid environment variable format: " .. env_var)
    end
  end

  local full_command = table.concat(command.args, " ")

  vim.fn.termopen(full_command, {
    env = envs,
    clear_env = true,
    stdin = opts.stdin,
    on_stdout = opts.on_stdout,
    on_exit = function(_, code, _)
      if code == 0 then
        print("Command executed successfully")
      else
        print("Command failed with exit code " .. code)
      end
    end,
  })

  vim.cmd("startinsert")
end

--- Load kubectl.json config file from data dir
---@param file_name string The filename to load
---@return table|nil The content of the file
function M.load_config(file_name)
  local file_path = vim.fn.stdpath("data") .. "/" .. file_name
  local file = io.open(file_path, "r")
  if not file then
    return nil
  end

  local json_data = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, json_data, { luanil = { object = true, array = true } })
  if ok then
    return decoded
  end
  return nil
end

--- Save to config file
--- @param file_name string The filename to save
--- @param data table The content to save
function M.save_config(file_name, data)
  local config_file = M.load_config("kubectl.json") or {}
  local merged = vim.tbl_deep_extend("force", config_file, data)
  local ok, encoded = pcall(vim.json.encode, merged)
  if ok then
    local file_path = vim.fn.stdpath("data") .. "/" .. file_name
    local file = io.open(file_path, "w")
    if file then
      file:write(encoded)
      file:close()
    end
  end
  return ok
end

return M
