local filter_view = require("kubectl.views.filter")
local namespace_view = require("kubectl.views.namespace")
local configmaps_view = require("kubectl.views.configmaps")
local deployments_view = require("kubectl.views.deployments")
local pods_view = require("kubectl.views.pods")
local secrets_view = require("kubectl.views.secrets")
local services_view = require("kubectl.views.services")
local state = require("kubectl.utils.state")
local view = require("kubectl.views")
local hl = require("kubectl.actions.highlight")

vim.api.nvim_buf_set_keymap(0, "n", "<leader>k", "", {
  noremap = true,
  silent = true,
  desc = "Toggle",
  callback = function()
    vim.cmd("bdelete!")
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

vim.api.nvim_buf_set_keymap(0, "n", "g?", "", {
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
        .. "deployments | "
        .. hl.symbols.pending
        .. "<4> "
        .. hl.symbols.clear
        .. "secrets",
    })
  end,
})
