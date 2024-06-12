local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local api = vim.api
local hl = require("kubectl.actions.highlight")
local view = require("kubectl.views")
local configmaps_view = require("kubectl.views.configmaps")
local deployments_view = require("kubectl.views.deployments")
local pod_view = require("kubectl.views.pods")
local secrets_view = require("kubectl.views.secrets")
local services_view = require("kubectl.views.services")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: "
        .. hl.symbols.pending
        .. "l"
        .. hl.symbols.clear
        .. " logs | "
        .. hl.symbols.pending
        .. " d "
        .. hl.symbols.clear
        .. "desc | "
        .. hl.symbols.pending
        .. "<1> "
        .. hl.symbols.clear
        .. "deployments | "
        .. hl.symbols.pending
        .. "<2> "
        .. hl.symbols.clear
        .. "pods | "
        .. hl.symbols.pending
        .. "<4> "
        .. hl.symbols.clear
        .. "secrets",
    })
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    configmaps_view.Configmaps()
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  callback = function()
    root_view.Root()
  end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, name = tables.getCurrentSelection(unpack({ 1, 2 }))
    if namespace and name then
      configmaps_view.ConfigmapsDesc(namespace, name)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "1", "", {
  noremap = true,
  silent = true,
  desc = "Deployments",
  callback = function()
    deployments_view.Deployments()
  end,
})

api.nvim_buf_set_keymap(0, "n", "2", "", {
  noremap = true,
  silent = true,
  desc = "Pods",
  callback = function()
    pod_view.Pods()
  end,
})

api.nvim_buf_set_keymap(0, "n", "3", "", {
  noremap = true,
  silent = true,
  desc = "Configmaps",
  callback = function()
    configmaps_view.Configmaps()
  end,
})

api.nvim_buf_set_keymap(0, "n", "4", "", {
  noremap = true,
  silent = true,
  desc = "Secrets",
  callback = function()
    secrets_view.Secrets()
  end,
})

api.nvim_buf_set_keymap(0, "n", "5", "", {
  noremap = true,
  silent = true,
  desc = "Services",
  callback = function()
    services_view.Services()
  end,
})

if not loop.is_running() then
  loop.start_loop(configmaps_view.Configmaps)
end
