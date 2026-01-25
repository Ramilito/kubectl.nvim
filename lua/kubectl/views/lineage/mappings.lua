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
      if lineage.is_loading or lineage.is_building_graph then
        vim.notify("Already loading, please wait...", vim.log.levels.INFO)
        return
      end
      -- Reset and reload cache, which will trigger graph build via autocmd
      lineage.is_loading = true
      lineage.graph = nil
      lineage.Draw() -- Show loading message
      lineage.load_cache()
    end,
  },
  ["<Plug>(kubectl.export_dot)"] = {
    desc = "export DOT",
    callback = function()
      local lineage = require("kubectl.views.lineage")
      if not lineage.graph or not lineage.graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end

      local client = require("kubectl.client")
      local ok, dot_content = pcall(client.export_lineage_dot, lineage.graph.tree_id)
      if not ok then
        vim.notify("Failed to export DOT: " .. tostring(dot_content), vim.log.levels.ERROR)
        return
      end

      -- Open in vertical split buffer
      vim.cmd("vsplit")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "lineage.dot")
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
      if not lineage.graph or not lineage.graph.tree_id then
        vim.notify("No lineage graph available", vim.log.levels.WARN)
        return
      end

      local client = require("kubectl.client")
      local ok, mermaid_content = pcall(client.export_lineage_mermaid, lineage.graph.tree_id)
      if not ok then
        vim.notify("Failed to export Mermaid: " .. tostring(mermaid_content), vim.log.levels.ERROR)
        return
      end

      -- Open in vertical split buffer
      vim.cmd("vsplit")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "lineage.mmd")
      vim.api.nvim_set_option_value("filetype", "mermaid", { buf = buf })
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
      local lines = vim.split(mermaid_content, "\n")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.export_dot)")
  mappings.map_if_plug_not_set("n", "gM", "<Plug>(kubectl.export_mermaid)")
end

return M
