local M = {}

-- Actions to exclude from resource-specific mappings (navigation/view actions)
local excluded_actions = {
  ["<Plug>(kubectl.select)"] = true,
  ["<Plug>(kubectl.select_fullscreen)"] = true,
  ["<Plug>(kubectl.logs)"] = true,
  ["<Plug>(kubectl.debug)"] = true,
  ["<Plug>(kubectl.browse)"] = true,
  ["<Plug>(kubectl.values)"] = true,
  ["<Plug>(kubectl.refresh)"] = true,
}

---Get code actions for current buffer
---@param _params table LSP request params (unused)
---@param callback function LSP callback
function M.get_code_actions(_params, callback)
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype

  if not ft:match("^k8s_") then
    vim.schedule(function()
      callback(nil, {})
    end)
    return
  end

  local resource_name = ft:gsub("^k8s_", "")
  local actions = {}

  -- Load resource-specific mappings only
  local ok, view_mappings = pcall(require, "kubectl.resources." .. resource_name .. ".mappings")
  if ok and view_mappings.overrides then
    for plug, mapping in pairs(view_mappings.overrides) do
      if not excluded_actions[plug] and mapping.callback then
        table.insert(actions, {
          title = mapping.desc or plug:match("<Plug>%(kubectl%.(.-)%)") or plug,
          kind = "source.kubectl",
          command = {
            title = mapping.desc or plug,
            command = "kubectl.execute_action",
            arguments = { plug },
          },
        })
      end
    end
  end

  -- Sort by title for consistent ordering
  table.sort(actions, function(a, b)
    return a.title < b.title
  end)

  vim.schedule(function()
    callback(nil, actions)
  end)
end

---Execute a code action by plug name
---@param plug string The plug mapping name
function M.execute(plug)
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype

  if not ft:match("^k8s_") then
    return
  end

  local resource_name = ft:gsub("^k8s_", "")

  -- Execute resource-specific mapping
  local ok, view_mappings = pcall(require, "kubectl.resources." .. resource_name .. ".mappings")
  if ok and view_mappings.overrides and view_mappings.overrides[plug] then
    local mapping = view_mappings.overrides[plug]
    if mapping.callback then
      mapping.callback()
    end
  end
end

return M
