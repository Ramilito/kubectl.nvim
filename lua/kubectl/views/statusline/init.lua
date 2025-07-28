local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local M = {
  interval = 2000,
}

M.View = function()
  local _ = manager.get_or_create("statusline")
  vim.o.laststatus = 3
  local timer = vim.uv.new_timer()

  timer:start(0, M.interval, function()
    vim.schedule(function()
      M.Draw()
    end)
  end)
end

M.Draw = function()
  local builder = manager.get("statusline")
  if builder then
    commands.run_async("get_statusline_async", {}, function(data, err)
      if err then
        return
      end
      builder.data = data
      builder.decodeJson()
      vim.schedule(function()
        pcall(vim.api.nvim_set_option_value, "statusline", M.process(builder.data), { scope = "global" })
      end)
    end)
  end
end

function M.process(data)
  local ready = data.ready or 0
  local not_ready = data.not_ready or 0
  local total = ready + not_ready
  local cpu = data.cpu_pct or 0
  local mem = data.mem_pct or 0

  local dot = (not_ready == 0) and "🟢" or "🔴"

  return string.format("%s %d/%d │ CPU %d │ MEM %d", dot, ready, total, cpu, mem)
end

return M
