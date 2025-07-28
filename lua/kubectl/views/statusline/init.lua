local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
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

  local GOOD = hl.symbols.success
  local BAD = hl.symbols.error

  local ready_ok = (not_ready == 0)
  local cpu_ok = (cpu < 90)
  local mem_ok = (mem < 90)

  local ready_hl = "%#" .. (ready_ok and GOOD or BAD) .. "#"
  local cpu_hl = "%#" .. (cpu_ok and GOOD or BAD) .. "#"
  local mem_hl = "%#" .. (mem_ok and GOOD or BAD) .. "#"
  local reset = "%*" -- reset back to default HL

  local dot = ready_ok and "🟢" or "🔴"
  local cpu_txt = string.format("%d", cpu) .. "%%"
  local mem_txt = string.format("%d", mem) .. "%%"

  return dot
    .. " "
    .. ready_hl
    .. ready
    .. "/"
    .. total
    .. reset
    .. " │ CPU "
    .. cpu_hl
    .. cpu_txt
    .. reset
    .. " │ MEM "
    .. mem_hl
    .. mem_txt
    .. reset
end

return M
