local buffers = require("kubectl.actions.buffers")
local M = {}

function M.View()
  local buf, win = buffers.floating_buffer("k8s_graphs", "K8s graphs")

  local client = require("kubectl.client")
  local ok, sess = pcall(client.start_dashboard, "overview")

  if not ok then
    vim.notify("graphs.start failed: " .. sess, vim.log.levels.ERROR)
    return
  end

  local function push_size()
    if vim.api.nvim_win_is_valid(win) then
      local w = vim.api.nvim_win_get_width(win)
      local h = vim.api.nvim_win_get_height(win)
      sess:resize(w, h)
    end
  end

  push_size()

  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      push_size()
    end,
  })

  local chan = vim.api.nvim_open_term(buf, {
    on_input = function(_, _, _, bytes)
      sess:write(bytes)
    end,
  })
  vim.cmd.startinsert()

  local timer = vim.uv.new_timer()
  timer:start(
    0,
    30,
    vim.schedule_wrap(function()
      repeat
        local chunk = sess:read_chunk()
        if chunk then
          vim.api.nvim_chan_send(chan, chunk)
        end
      until not chunk
      if not sess:open() then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        vim.api.nvim_chan_send(chan, "\r\n[UI exited]\r\n")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)
  )
end

return M
