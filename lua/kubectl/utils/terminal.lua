local buffers = require("kubectl.actions.buffers")

local M = {}

--- Attach a bidirectional session to a terminal buffer
--- @param sess table Session object with read_chunk, write, open, close methods
--- @param buf number Buffer handle
--- @param win number Window handle
function M.attach_session(sess, buf, win)
  local chan = vim.api.nvim_open_term(buf, {
    on_input = function(_, _, _, data)
      sess:write(data)
    end,
  })

  -- Send initial newline to trigger shell prompt
  sess:write("\n")

  vim.cmd.startinsert()

  local timer = vim.uv.new_timer()
  if not timer then
    vim.notify("Timer failed to initialize", vim.log.levels.ERROR)
    return
  end
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
        sess:close()
        vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
        -- Small delay to let user see the message, then close
        vim.defer_fn(function()
          vim.cmd("stopinsert")
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end, 1000)
      end
    end)
  )
end

--- Spawn a terminal with a session
--- @param title string Window title
--- @param key string Buffer key for registration
--- @param fn function Function that returns a session
--- @param is_fullscreen boolean Whether to use fullscreen buffer
--- @param ... any Additional arguments passed to fn
function M.spawn_terminal(title, key, fn, is_fullscreen, ...)
  -- Show loading indicator during connection
  local loading_buf, loading_win = buffers.floating_dynamic_buffer("k8s_loading", "Connecting...", nil, {
    enter = false,
    width = 20,
    height = 1,
    skip_fit = true,
  })
  buffers.set_content(loading_buf, { content = { " Connecting..." } })
  vim.cmd("redraw")

  local ok, sess = pcall(fn, ...)

  -- Close loading indicator
  if vim.api.nvim_win_is_valid(loading_win) then
    vim.api.nvim_win_close(loading_win, true)
  end

  if not ok or sess == nil then
    vim.notify("kubectl-client error: " .. tostring(sess), vim.log.levels.ERROR)
    return
  end

  -- Delete any existing buffer with the same name to avoid "Terminal already connected" error
  local existing_buf = buffers.get_buffer_by_name(key .. " | " .. title)
  if existing_buf and vim.api.nvim_buf_is_valid(existing_buf) then
    vim.api.nvim_buf_delete(existing_buf, { force = true })
  end

  local buf, win
  if is_fullscreen then
    buf, win = buffers.buffer(key, title)
  else
    buf, win = buffers.floating_buffer(key, title)
  end

  vim.api.nvim_set_current_buf(buf)
  vim.schedule(function()
    M.attach_session(sess, buf, win)
  end)
end

return M
