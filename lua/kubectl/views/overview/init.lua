local uv = vim.loop
local api = vim.api
local M = {}
function M.View(cancellationToken)
  -- dimensions for the floating window
  local win_w = math.floor(vim.o.columns * 0.70)
  local win_h = math.floor(vim.o.lines * 0.40)

  -- 1. scratch terminal buffer (no external job)
  local buf = api.nvim_create_buf(false, true)
  local chan = api.nvim_open_term(buf, {}) -- libvterm instance

  -- 2. floating window
  api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 2,
    col = 4,
    width = win_w,
    height = win_h,
    border = "rounded",
  })

  -- 3. start the PTY-powered dashboard in Rust
  --    Rust returns the *master* FD as an integer
  local master_fd = require("kubectl_client").start_dashboard(win_w, win_h)

  -- 4. pump PTY → channel using libuv
  local pipe = uv.new_pipe(false)
  pipe:open(master_fd)

  uv.read_start(pipe, function(err, data)
    if err then
      return
    end -- ignore errors for this PoC
    if not data then
      return
    end -- EOF
    vim.schedule(function()
      api.nvim_chan_send(chan, data)
    end)
  end)

  -- 5. stop reading when the buffer is wiped (user closes window)
  api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      uv.read_stop(pipe)
      pipe:close()
    end,
  })
end

function M.Draw(cancellationToken) end

return M
