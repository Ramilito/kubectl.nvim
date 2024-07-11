local M = {}

--- Execute a shell command synchronously
--- @param cmd string The command to execute
--- @param args string[] The arguments for the command
--- @return string The result of the command execution
function M.shell_command(cmd, args, opts)
  opts = opts or {}
  local result = ""
  local error_result = ""

  table.insert(args, 1, cmd)

  local job = vim.system(args, {
    text = true,
    env = opts.env,
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

  if exit_code ~= 0 then
    vim.notify(error_result, vim.log.levels.ERROR)
  end

  return result
end

--- Execute a shell command asynchronously
--- @param cmd string The command to execute
--- @param args string[] The arguments for the command
--- @param on_exit? function The callback function to execute when the command exits
--- @param on_stdout? function The callback function to execute when there is stdout output (optional)
function M.shell_command_async(cmd, args, on_exit, on_stdout)
  local result = ""

  table.insert(args, 1, cmd)

  vim.system(args, {
    text = true,
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

    stderr = function(_, data)
      vim.schedule(function()
        if data then
          vim.notify(data, vim.log.levels.ERROR)
        end
      end)
    end,
  }, function()
    if on_exit then
      on_exit(result)
    end
  end)
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
--- @param cmd string The command to execute
--- @param args string|string[] The arguments for the command
function M.execute_terminal(cmd, args, opts)
  opts = opts or {}
  if type(args) == "table" then
    args = table.concat(args, " ")
  end
  local full_command = cmd .. " " .. args

  vim.fn.termopen(full_command, {
    env = opts.env,
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

return M
