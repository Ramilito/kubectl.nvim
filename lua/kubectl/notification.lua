local actions = require("kubectl.actions.actions")
local M = {}

function M.process_row(rows)
  local width = 0
  local max_width = 100
  for _, value in ipairs(rows) do
    if #value > width then
      width = #value
      if #value > max_width then
        width = max_width
      end
    end
  end

  local aligned_lines = {}
  for _, line in ipairs(rows) do
    local padding = string.rep(" ", width - #line)
    if #line > max_width then
      padding = string.rep(" ", width - max_width)
      line = string.sub(line, 1, max_width - 3)
      line = line .. "..."
    end
    table.insert(aligned_lines, padding .. line)
  end

  return aligned_lines, width
end

function M.Close()
  actions.notification_buffer({ "" }, { close = true })
end
function M.Open(rows)
  local content, width = M.process_row(rows)
  actions.notification_buffer(content, { width = width, close = false })
end

return M
