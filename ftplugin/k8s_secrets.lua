local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local api = vim.api
local secrets_view = require("kubectl.views.secrets")
local configmaps_view = require("kubectl.views.configmaps")
local deployments_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local pod_view = require("kubectl.views.pods")
local services_view = require("kubectl.views.services")
local view = require("kubectl.views")

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
        .. "<3> "
        .. hl.symbols.clear
        .. "configmaps",
    })
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    secrets_view.Secrets()
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  callback = function()
    root_view.Root()
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

api.nvim_buf_set_keymap(0, "n", "5", "", {
  noremap = true,
  silent = true,
  desc = "Services",
  callback = function()
    services_view.Services()
  end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, name = tables.getCurrentSelection(unpack({ 1, 2 }))
    if namespace and name then
      secret_view.SecretDesc(namespace, name)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

if not loop.is_running() then
  loop.start_loop(secret_view.Secrets)
end
