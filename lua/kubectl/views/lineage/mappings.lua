local mappings = require("kubectl.mappings")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    desc = "go to",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local kind, ns, name = lineage.getCurrentSelection()
      if name and ns then
        local state = require("kubectl.state")
        local view = require("kubectl.views")
        vim.api.nvim_set_option_value("modified", false, { buf = 0 })
        vim.cmd.fclose()

        state.filter_key = "metadata.name=" .. name
        if ns then
          state.filter_key = state.filter_key .. ",metadata.namespace=" .. ns
        end
        view.resource_or_fallback(kind)
      else
        vim.notify("Failed to select resource.", vim.log.levels.ERROR)
      end
    end,
  },
  ["<Plug>(kubectl.refresh)"] = {
    desc = "refresh cache",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      lineage.refresh()
    end,
  },
  ["<Plug>(kubectl.export_dot)"] = {
    desc = "export DOT",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local definition = require("kubectl.views.lineage.definition")
      local client = require("kubectl.client")

      if not lineage.graph or not lineage.graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end

      -- Parse the current line to get resource key
      local line = vim.api.nvim_get_current_line()
      local resource_key = definition.parse_line_resource_key(line)

      if not resource_key then
        vim.notify("Could not parse resource from current line", vim.log.levels.ERROR)
        return
      end

      -- Export subgraph for the selected resource
      ---@diagnostic disable-next-line: undefined-field
      local ok, dot_content = pcall(client.export_lineage_subgraph_dot, lineage.graph.tree_id, resource_key)
      if not ok then
        vim.notify("Failed to export DOT: " .. tostring(dot_content), vim.log.levels.ERROR)
        return
      end

      -- Open in vertical split buffer
      vim.cmd("vsplit")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "lineage_subgraph.dot")
      vim.api.nvim_set_option_value("filetype", "dot", { buf = buf })
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
      local lines = vim.split(dot_content, "\n")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end,
  },
  ["<Plug>(kubectl.export_mermaid)"] = {
    desc = "export Mermaid",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local definition = require("kubectl.views.lineage.definition")
      local client = require("kubectl.client")

      if not lineage.graph or not lineage.graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end

      -- Parse the current line to get resource key
      local line = vim.api.nvim_get_current_line()
      local resource_key = definition.parse_line_resource_key(line)

      if not resource_key then
        vim.notify("Could not parse resource from current line", vim.log.levels.ERROR)
        return
      end

      -- Export subgraph for the selected resource
      ---@diagnostic disable-next-line: undefined-field
      local ok, mermaid_content = pcall(client.export_lineage_subgraph_mermaid, lineage.graph.tree_id, resource_key)
      if not ok then
        vim.notify("Failed to export Mermaid: " .. tostring(mermaid_content), vim.log.levels.ERROR)
        return
      end

      -- Open in vertical split buffer
      vim.cmd("vsplit")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "lineage_subgraph.mmd")
      vim.api.nvim_set_option_value("filetype", "mermaid", { buf = buf })
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
      local lines = vim.split(mermaid_content, "\n")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end,
  },
  ["<Plug>(kubectl.toggle_orphan_filter)"] = {
    desc = "toggle orphan filter",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      lineage.orphan_filter_enabled = not lineage.orphan_filter_enabled
      local status = lineage.orphan_filter_enabled and "enabled" or "disabled"
      vim.notify("Orphan filter " .. status, vim.log.levels.INFO)
      lineage.Draw()
    end,
  },
  ["<Plug>(kubectl.impact_analysis)"] = {
    desc = "impact analysis",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      local definition = require("kubectl.views.lineage.definition")
      local client = require("kubectl.client")

      if not lineage.graph or not lineage.graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end

      -- Parse the current line to get resource key
      local line = vim.api.nvim_get_current_line()
      local resource_key = definition.parse_line_resource_key(line)

      if not resource_key then
        vim.notify("Could not parse resource from current line", vim.log.levels.ERROR)
        return
      end

      -- Call Rust to compute impact
      local ok, impact_json = pcall(client.compute_lineage_impact, lineage.graph.tree_id, resource_key)
      if not ok then
        vim.notify("Failed to compute impact: " .. tostring(impact_json), vim.log.levels.ERROR)
        return
      end

      local impacted = vim.json.decode(impact_json)
      definition.display_impact_results(impacted, resource_key)
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
