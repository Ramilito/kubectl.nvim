local mappings = require("kubectl.mappings")

local M = {}

--- Get the resource key for the node under cursor, or nil.
--- @return string|nil
local function cursor_resource_key()
  local lineage = require("kubectl.views.lineage")
  local node = lineage.get_line_node(vim.api.nvim_win_get_cursor(0)[1])
  if not node then
    return nil
  end
  return node.key
end

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    desc = "go to",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local actions = require("kubectl.views.lineage.actions")
      local kind, ns, name = lineage.getCurrentSelection()
      if kind and name then
        actions.go_to_resource(kind, ns, name)
      end
    end,
  },
  ["<Plug>(kubectl.refresh)"] = {
    desc = "refresh cache",
    callback = function()
      require("kubectl.views.lineage").refresh()
    end,
  },
  ["<Plug>(kubectl.export_dot)"] = {
    desc = "export DOT",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local actions = require("kubectl.views.lineage.actions")
      local graph = lineage.get_graph()
      if not graph or not graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end
      local resource_key = cursor_resource_key()
      if not resource_key then
        vim.notify("No resource under cursor", vim.log.levels.ERROR)
        return
      end
      actions.export(graph.tree_id, resource_key, "dot")
    end,
  },
  ["<Plug>(kubectl.export_mermaid)"] = {
    desc = "export Mermaid",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local actions = require("kubectl.views.lineage.actions")
      local graph = lineage.get_graph()
      if not graph or not graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end
      local resource_key = cursor_resource_key()
      if not resource_key then
        vim.notify("No resource under cursor", vim.log.levels.ERROR)
        return
      end
      actions.export(graph.tree_id, resource_key, "mermaid")
    end,
  },
  ["<Plug>(kubectl.toggle_orphan_filter)"] = {
    desc = "toggle orphan filter",
    callback = function()
      require("kubectl.views.lineage").toggle_orphan_filter()
    end,
  },
  ["<Plug>(kubectl.impact_analysis)"] = {
    desc = "impact analysis",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local actions = require("kubectl.views.lineage.actions")
      local graph = lineage.get_graph()
      if not graph or not graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end
      local resource_key = cursor_resource_key()
      if not resource_key then
        vim.notify("No resource under cursor", vim.log.levels.ERROR)
        return
      end
      actions.impact_analysis(graph.tree_id, resource_key)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gO", "<Plug>(kubectl.toggle_orphan_filter)")
  mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.export_dot)")
  mappings.map_if_plug_not_set("n", "gM", "<Plug>(kubectl.export_mermaid)")
  mappings.map_if_plug_not_set("n", "gI", "<Plug>(kubectl.impact_analysis)")
end

return M
