local M = {}

function M.shell_command_async(cmd, args, on_exit, on_stdout)
  local loaded, Job = pcall(require, "plenary.job")
  print(vim.inspect(args))
  print(cmd)
  if not loaded then
    vim.notify("plenary.nvim is not installed. Please install it to use this feature.", vim.log.levels.ERROR)
    return
  end
  local result = {}
  Job:new({
    command = cmd,
    args = args,
    on_stdout = function(_, data)
      table.insert(result, data)
      if on_stdout then
        on_stdout(data)
      end
    end,
    on_stderr = function(_, data)
      vim.schedule(function()
        if data then
          vim.notify(data, vim.log.levels.ERROR)
        end
      end)
    end,
    on_exit = function(_, _)
      if on_exit then
        on_exit(table.concat(result, "\n"))
      end
    end,
  }):start()
end

function M.execute_shell_command(cmd, args)
  if type(args) == "table" then
    args = table.concat(args, " ")
  end
  local full_command = cmd .. " " .. args
  local handle = io.popen(full_command, "r")
  if handle == nil then
    return { "Failed to execute command: " .. cmd }
  end
  local result = handle:read("*a")
  handle:close()

  return result
end

function M.execute_terminal(cmd, args)
  local full_command = cmd .. " " .. table.concat(args, " ")
  vim.fn.termopen(full_command, {
    on_exit = function(_, code, _)
      if code == 0 then
        print("Command executed successfully")
      else
        print("Command failed with exit code " .. code)
      end
    end,
  })
end

return M
