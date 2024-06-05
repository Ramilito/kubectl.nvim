local M = {}

function M.shell_command_async(cmd, args, callback)
  -- local start_time = vim.fn.reltime()
  -- local obj = vim.system({ "kubectl" }, { text = true }):wait()
  --
  -- local elapsed_time = vim.fn.reltimefloat(vim.fn.reltime(start_time))
  -- print("Neovim kubectl command to file elapsed time: " .. elapsed_time .. " seconds")

  local full_command = {}

  table.insert(full_command, cmd)
  for _, arg in ipairs(args) do
    table.insert(full_command, arg)
  end

  vim.system(full_command, { text = true }, callback)
end

-- function M.shell_command(cmd, args, callback)
--   local loaded, Job = pcall(require, "plenary.job")
--   if not loaded then
--     vim.notify("plenary.nvim is not installed. Please install it to use this feature.", vim.log.levels.ERROR)
--     return
--   end
--
--   Job:new({
--     command = cmd,
--     args = args,
--     on_stdout = function(_, data)
--       callback(data)
--     end,
--     on_stderr = function(_, data)
--       callback(data)
--     end,
--   }):start()
-- end

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
