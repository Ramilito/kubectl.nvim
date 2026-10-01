local argocd_view = require("kubectl.resources.argocd")
local mappings = require("kubectl.mappings")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.describe)"] = {
    noremap = true,
    silent = true,
    desc = "Describe ArgoCD resource",
    callback = function()
      local name, ns = argocd_view.getCurrentSelection()
      if name then
        argocd_view.Desc(name, ns)
      end
    end,
  },

  ["<Plug>(kubectl.yaml)"] = {
    noremap = true,
    silent = true,
    desc = "View YAML",
    callback = function()
      local name, ns = argocd_view.getCurrentSelection()
      if name then
        argocd_view.Yaml(name, ns)
      end
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.describe)")
  mappings.map_if_plug_not_set("n", "gy", "<Plug>(kubectl.yaml)")
end

return M
