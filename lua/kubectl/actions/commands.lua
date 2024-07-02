local M = {}

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

    stderr = function(err, data)
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
