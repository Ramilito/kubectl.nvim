local M = {}

--- Execute a shell command synchronously
--- @param cmd string The command to execute
--- @param args string[] The arguments for the command
--- @param opts { env: string, on_stdout: function, stdin: string }|nil The arguments for the command
--- @return string The result of the command execution
function M.shell_command(cmd, args, opts)
  opts = opts or {}
  local result = ""
  local error_result = ""

  table.insert(args, 1, cmd)

  local job = vim.system(args, {
    text = true,
    env = opts.env,
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

--- Execute a shell command asynchronously
--- @param cmd string The command to execute
--- @param args string[] The arguments for the command
--- @param on_exit? function The callback function to execute when the command exits
--- @param on_stdout? function The callback function to execute when there is stdout output (optional)
--- @param opts { continue_token: string, env: string, stdin: string }|nil The arguments for the command
function M.shell_command_async(cmd, args, on_exit, on_stdout, opts)
  opts = opts or {}
  local system_cmd = {}
  local result = ""
  table.insert(system_cmd, cmd)
  for _, value in ipairs(args) do
    table.insert(system_cmd, value)
  end
  if opts.continue_token then
    system_cmd[#system_cmd] = system_cmd[#system_cmd] .. "&continue=" .. opts.continue_token
  end

  local handle = vim.system(system_cmd, {
    text = true,
    stdin = opts.stdin,
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
      local continue_token = string.match(result, '"continue":"(.-)"')
      if continue_token then
        M.shell_command_async(cmd, args, on_exit, on_stdout, { continue_token = continue_token, limit = 100 })
      end
    end
  end)

  return handle
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

function M.load_config(file_name)
  local file_path = vim.fn.stdpath("data") .. "/" .. file_name
  local file = io.open(file_path, "r")
  if not file then
    return nil
  end

  local json_data = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, json_data)
  if ok then
    return decoded
  end
  return nil
end

--- Save to config file
--- @param file_name string The filename to save
--- @param data table The content to save
function M.save_config(file_name, data)
  local ok, encoded = pcall(vim.json.encode, data)
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

function M.restore_session()
  local session = M.load_config("kubectl.session.json")
  if session then
    local ok, view = pcall(require, "kubectl.views." .. string.lower(session.view))
    if ok then
      view.View()
    else
      local pod_view = require("kubectl.views.pods")
      pod_view.View()
    end
  else
    local pod_view = require("kubectl.views.pods")
    pod_view.View()
  end
end

return M
