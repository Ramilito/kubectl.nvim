local buffers = require("kubectl.actions.buffers")
local api = vim.api
local M = {}

function M.View()
  local buf, win = buffers.floating_buffer("k8s_top", "Top")
  api.nvim_win_set_config(win, vim.tbl_extend("force", api.nvim_win_get_config(win), { border = "none" }))

  api.nvim_set_current_win(win)
  local job_id = vim.fn.jobstart({ "tail", "-f", "/dev/null" }, {
    term = true,
    on_exit = function()
      vim.schedule(function()
        if api.nvim_win_is_valid(win) then
          api.nvim_win_close(win, true)
        end
        if api.nvim_buf_is_valid(buf) then
          api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end,
  })
  vim.cmd.startinsert()

  local info = api.nvim_get_chan_info(job_id)
  local pid = vim.fn.jobpid(job_id)
  require("kubectl_client").start_dashboard(info.pty, "top", pid)

  -- 5 ▸ close everything when the buffer disappears
  api.nvim_create_autocmd({ "BufWipeout", "BufHidden" }, {
    buffer = buf,
    once = true,
    callback = function()
      vim.fn.jobstop(job_id)
      require("kubectl_client").stop_dashboard()
    end,
  })
end

return M
