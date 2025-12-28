local M = {}

--- Factory for creating safe callbacks that extract selection and call handler
--- Reduces the 8-line callback pattern to a single function call
---@param view_module table The resource view module with getCurrentSelection
---@param handler_func function The function to call with (name, ns) or (name)
---@param is_cluster_scoped? boolean Whether resource is cluster-scoped (no namespace)
---@return function callback The callback function for the mapping
function M.safe_callback(view_module, handler_func, is_cluster_scoped)
  return function()
    local name, ns
    if is_cluster_scoped then
      name = view_module.getCurrentSelection()
    else
      name, ns = view_module.getCurrentSelection()
    end

    if not name then
      vim.notify("Failed to extract resource name or namespace.", vim.log.levels.ERROR)
      return
    end

    if is_cluster_scoped then
      handler_func(name)
    else
      handler_func(name, ns)
    end
  end
end

return M
