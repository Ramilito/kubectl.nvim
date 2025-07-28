local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local M = {
  interval = 30000,
}

M.View = function()
  local builder = manager.get_or_create("statusline")

  builder.original_values = {
    laststatus = vim.o.laststatus,
    statusline = vim.o.statusline,
  }
  vim.o.laststatus = 3
  local timer = vim.uv.new_timer()

  timer:start(5000, M.interval, function()
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
  local crit_events = data.crit_events or 0

  local GOOD = hl.symbols.success
  local BAD = hl.symbols.error

  local ready_ok = (not_ready == 0)
  local cpu_ok = (cpu < 90)
  local mem_ok = (mem < 90)
  local evt_ok = (crit_events == 0)

  local hl_ready = "%#" .. (ready_ok and GOOD or BAD) .. "#"
  local hl_cpu = "%#" .. (cpu_ok and GOOD or BAD) .. "#"
  local hl_mem = "%#" .. (mem_ok and GOOD or BAD) .. "#"
  local hl_evt = "%#" .. (evt_ok and GOOD or BAD) .. "#"

  local reset = "%*"

  local dot = ready_ok and "🟢" or "🔴"
  local cpu_txt = string.format("%d", cpu) .. "%%"
  local mem_txt = string.format("%d", mem) .. "%%"

  local core = dot
    .. " "
    .. hl_ready
    .. ready
    .. "/"
    .. total
    .. reset
    .. " │ CPU "
    .. hl_cpu
    .. cpu_txt
    .. reset
    .. " │ MEM "
    .. hl_mem
    .. mem_txt
    .. reset
    .. " │ EVENTS "
    .. hl_evt
    .. crit_events
    .. reset
  return "%=" .. core .. "%="
end

return M
