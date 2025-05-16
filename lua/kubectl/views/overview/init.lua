local buffers = require("kubectl.actions.buffers")
local uv = vim.loop
local api = vim.api
local M = {}
function M.View(cancellationToken)
  local buf, win = buffers.floating_buffer("k8s_overview", "Overview")
  local win_config = vim.api.nvim_win_get_config(win)
  local chan = api.nvim_open_term(buf, {})

  local master_fd = require("kubectl_client").start_dashboard(win_config.width, win_config.height)

  -- 4. pump PTY → channel using libuv
  local pipe = uv.new_pipe(false)
  pipe:open(master_fd)

  uv.read_start(pipe, function(err, data)
    if err then
      return
    end
    if not data then
      return
    end
    vim.schedule(function()
      api.nvim_chan_send(chan, data)
    end)
  end)

  api.nvim_create_autocmd({ "BufWipeout", "BufHidden" }, {
    buffer = buf,
    once = true,
    callback = function()
      require("kubectl_client").stop_dashboard()
      uv.read_stop(pipe)
      pipe:close()
    end,
  })
end

function M.Draw(cancellationToken) end

return M
