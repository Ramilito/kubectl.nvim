local config = require("kubectl.config")
local configmaps_view = require("kubectl.views.configmaps")
local deployments_view = require("kubectl.views.deployments")
local filter_view = require("kubectl.views.filter")
local kube = require("kubectl.utils.kube")
local namespace_view = require("kubectl.views.namespace")
local pods_view = require("kubectl.views.pods")
local secrets_view = require("kubectl.views.secrets")
local services_view = require("kubectl.views.services")
local state = require("kubectl.utils.state")

local M = {}

function M.register()
  vim.api.nvim_buf_set_keymap(0, "n", config.options.mappings.exit, "", {
    noremap = true,
    silent = true,
    desc = "Toggle",
    callback = function()
      kube.stop_kubectl_proxy()()
      vim.api.nvim_buf_delete(0, { force = true })
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-f>", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      filter_view.filter()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-n>", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      namespace_view.Namespace()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "s", "", {
    noremap = false,
    silent = true,
    desc = "Sort",
    callback = function()
      local current_word = vim.fn.expand("<cword>")
      state.setSortBy(current_word)
      vim.api.nvim_input("R")
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "1", "", {
    noremap = true,
    silent = true,
    desc = "Deployments",
    callback = function()
      deployments_view.Deployments()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "2", "", {
    noremap = true,
    silent = true,
    desc = "Pods",
    callback = function()
      pods_view.Pods()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "3", "", {
    noremap = true,
    silent = true,
    desc = "Configmaps",
    callback = function()
      configmaps_view.Configmaps()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "4", "", {
    noremap = true,
    silent = true,
    desc = "Secrets",
    callback = function()
      secrets_view.Secrets()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "5", "", {
    noremap = true,
    silent = true,
    desc = "Services",
    callback = function()
      services_view.Services()
    end,
  })
end
return M
