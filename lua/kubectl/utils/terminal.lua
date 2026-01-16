local buffers = require("kubectl.actions.buffers")
local state = require("kubectl.state")

local M = {}

--- Show a loading indicator window
--- @param message string The loading message to display
--- @return number buf Buffer handle
--- @return number win Window handle
local function show_loading(message)
  local width = #message + 4
  local height = 3
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  " .. message, "" })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.cmd("redraw")

  return buf, win
end

--- Close the loading indicator
--- @param buf number Buffer handle
--- @param win number Window handle
local function close_loading(buf, win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

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
        vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
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
  local loading_buf, loading_win = show_loading("Connecting...")

  local ok, sess = pcall(fn, ...)

  -- Close loading indicator
  close_loading(loading_buf, loading_win)

  if not ok or sess == nil then
    vim.notify("kubectl-client error: " .. tostring(sess), vim.log.levels.ERROR)
    return
  end

  local buf, win
  if is_fullscreen then
    buf, win = buffers.buffer(key, title)
    state.picker_register(key, title, buffers.buffer, { key, title })
  else
    buf, win = buffers.floating_buffer(key, title)
    state.picker_register(key, title, buffers.floating_buffer, { key, title })
  end

  vim.api.nvim_set_current_buf(buf)
  vim.schedule(function()
    M.attach_session(sess, buf, win)
  end)
end

return M
