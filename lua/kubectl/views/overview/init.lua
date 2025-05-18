local buffers = require("kubectl.actions.buffers")
local api = vim.api
local M = {}

function M.View()
  local buf, win = buffers.floating_buffer("k8s_overview", "Overview")
  api.nvim_win_set_config(win, vim.tbl_extend("force", api.nvim_win_get_config(win), { border = "none" }))

  api.nvim_set_current_win(win)
  local job_id = vim.fn.jobstart({ "tail", "-f", "/dev/null" }, { term = true })

  -- 3 ▸ find the PTY path Neovim allocated, e.g. "/dev/pts/11"
  local info = api.nvim_get_chan_info(job_id)
  local pty_path = info.pty -- verified in :h channel-info

  -- 4 ▸ start the dashboard, give it the *path* string
  require("kubectl_client").start_dashboard(pty_path)

  -- 5 ▸ close everything when the buffer disappears
  api.nvim_create_autocmd({ "BufWipeout", "BufHidden" }, {
    buffer = buf,
    once = true,
    callback = function()
      vim.fn.jobstop(job_id) -- kill the sleeping job
      require("kubectl_client").stop_dashboard()
    end,
  })
end

return M
