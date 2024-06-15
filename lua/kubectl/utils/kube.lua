local timeme = require("kubectl.utils.timeme")
local M = {}
function M.startProxy(callback)
  timeme.start()
  local jobId = vim.fn.jobstart("kubectl proxy --port=8080", {
    on_stdout = function()
      timeme.stop()
    end,
    on_exit = function(job_id, code, event)
      print("kubectl proxy exited with code", code)
    end,
  })
  vim.schedule(function()
    callback()
  end)

  -- Function to stop the kubectl proxy job
  local function stop_kubectl_proxy()
    if jobId ~= nil then
      vim.fn.jobstop(jobId)
      print("kubectl proxy stopped")
      jobId = nil
    end
  end

  -- Set up an autocommand to stop the kubectl proxy when Neovim exits
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = stop_kubectl_proxy,
  })

  -- Return the job id for reference
  return jobId
end

return M
