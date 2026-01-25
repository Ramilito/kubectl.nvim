local M = {}

local map_opts = { noremap = true, silent = true }

M.overrides = {
  ["<Plug>(kubectl.select)"] = vim.tbl_extend("force", map_opts, {
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
  }),
  ["<Plug>(kubectl.refresh)"] = vim.tbl_extend("force", map_opts, {
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
  }),
}

return M
