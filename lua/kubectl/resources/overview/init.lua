local buffers = require("kubectl.actions.buffers")
local M = {}

function M.View()
  local buf, win = buffers.floating_buffer("k8s_overview", "K8s Overview")

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

  -- Create autocmd group for proper cleanup
  local augroup = vim.api.nvim_create_augroup("KubectlOverview_" .. buf, { clear = true })

  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
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

  local function cleanup()
    -- Delete autocmd group
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    -- Delete buffer to prevent artifacts on reopen
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

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
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        cleanup()
      end
    end)
  )

  -- Also cleanup when window is closed manually
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(win),
    once = true,
    callback = function()
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
      cleanup()
    end,
  })
end

return M
