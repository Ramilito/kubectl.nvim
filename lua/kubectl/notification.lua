local actions = require("kubectl.actions.actions")
local config = require("kubectl.config")
local M = {}

function M.process_row(rows)
  local width = 40
  local max_width = 40
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
  if not config.options.notifications.enabled then
    return
  end
  vim.defer_fn(function()
    actions.notification_buffer({ "" }, { close = true })
  end, 300)
end
function M.Add(rows)
  if not config.options.notifications.enabled then
    return
  end
  vim.schedule(function()
    local content, width = M.process_row(rows)
    actions.notification_buffer(content, { width = width, close = false, append = true })
  end)
end

function M.Open(rows)
  if not config.options.notifications.enabled then
    return
  end
  vim.schedule(function()
    local content, width = M.process_row(rows)
    actions.notification_buffer(content, { width = width, close = false, append = false })
  end)
end

return M
