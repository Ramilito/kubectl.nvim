local actions = require("kubectl.actions.actions")
local config = require("kubectl.config")
local state = require("kubectl.state")
local M = {}

local spinners = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}

local vertical_bar = {
  "▁",
  "▂",
  "▃",
  "▄",
  "▅",
  "▆",
  "▇",
  "█",
}
function M.process_row(rows)
  local width = 40
  local max_width = 40
  local aligned_lines = {}

  for _, value in ipairs(rows) do
    if #value > width then
      width = #value
      if #value > max_width then
        width = max_width
      end
    end
  end

  for _, line in ipairs(rows) do
    local padding = string.rep(" ", width - #line)
    if #line > max_width then
      padding = string.rep(" ", width - max_width)
      line = string.sub(line, 1, max_width - 3)
      line = line .. "..."
    end

    table.insert(aligned_lines, padding .. line)
  end

  return aligned_lines
end

function M.Add(rows)
  if not config.options.notifications.enabled then
    return
  end
  local content = M.process_row(rows)
  for _, value in ipairs(content) do
    table.insert(state.notifications, 1, value)
    if #state.notifications > 10 then
      table.remove(state.notifications)
    end
  end
  vim.schedule(function()
    actions.notification_buffer({ close = false, append = false })
  end)
end

return M
