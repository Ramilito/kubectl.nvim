local M = {}

function M.continuous_shell_command(cmd, args)
  local loaded, Job = pcall(require, "plenary.job")
  if not loaded then
    vim.notify("plenary.nvim is not installed. Please install it to use this feature.")
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  Job:new({
    command = cmd,
    args = args,
    on_stdout = function(err, data)
      if err then
        print("Error: ", err)
      else
        vim.schedule(function()
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { data })
          vim.api.nvim_set_option_value("modified", false, { buf = buf })
        end)
      end
    end,
    on_stderr = function(err, data)
      if err then
        print("Error: ", err)
      else
        vim.schedule(function()
          vim.api.nvim_err_writeln(data)
        end)
      end
    end,
  }):start()
end

-- Function to execute a shell command and return the output as a table of strings
function M.execute_shell_command(cmd, args)
  local full_command = cmd .. " " .. table.concat(args, " ")
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
