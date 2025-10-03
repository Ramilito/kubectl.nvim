local config = require("kubectl.config")
local state = require("kubectl.state")

local M = {}

function M.on_prompt_input(input)
  if input == "" then
    return
  end
  local history = state.alias_history
  local history_size = config.options.alias.max_history

  local result = {}
  local exists = false
  for i = 1, math.min(history_size, #history) do
    if history[i] ~= input then
      table.insert(result, vim.trim(history[i]))
    else
      table.insert(result, 1, vim.trim(input))
      exists = true
    end
  end

  if not exists and input ~= "" then
    table.insert(result, 1, input)
    if #result > history_size then
      table.remove(result, #result)
    end
  end

  state.alias_history = result

  local parsed_input = string.lower(vim.trim(input))
  local view = require("kubectl.views")
  view.resource_or_fallback(parsed_input)
end

function M.merge_views(cached_resources, views_table)
  -- merge the data from the viewsTable with the data from the cached_api_resources
  for _, views in pairs(views_table) do
    for _, view in ipairs(views) do
      if not vim.tbl_contains(vim.tbl_keys(cached_resources), view) then
        cached_resources[view] = { name = view }
      end
    end
  end
  return cached_resources
end

return M
