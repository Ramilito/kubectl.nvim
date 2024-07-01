local actions = require("kubectl.actions.actions")
local config = require("kubectl.config")
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

  return aligned_lines, width
end

function M.Close()
  if not config.options.notifications.enabled then
    return
  end

  if not config.options.notifications.verbose then
    local width, content = 5, {}
    content[1] = vertical_bar[#vertical_bar]
    vim.schedule(function()
      actions.notification_buffer(content, { width = width, close = false, append = true })
    end)
  end

  vim.defer_fn(function()
    actions.notification_buffer({ "" }, { close = true })
  end, 300)
end

function M.Add(rows)
  if not config.options.notifications.enabled then
    return
  end

  local content, width = M.process_row(rows)
  if not config.options.notifications.verbose then
    width = 5
    for index, value in ipairs(content) do
      content[index] = vertical_bar[index + 2]
    end
  end

  vim.schedule(function()
    actions.notification_buffer(content, { width = width, close = false, append = true })
  end)
end

function M.Open(rows)
  local content, width = M.process_row(rows)
  if not config.options.notifications.enabled then
    return
  end
  if not config.options.notifications.verbose then
    width = 5
    for index, value in ipairs(content) do
      content[index] = vertical_bar[index]
    end
  end
  vim.schedule(function()
    actions.notification_buffer(content, { width = width, close = false, append = false })
  end)
end

return M
