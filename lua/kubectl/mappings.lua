local M = {}

function M.register()
  local config = require("kubectl.config")
  local kube = require("kubectl.actions.kube")
  vim.api.nvim_buf_set_keymap(0, "n", config.options.mappings.exit, "", {
    noremap = true,
    silent = true,
    desc = "Toggle",
    callback = function()
      kube.stop_kubectl_proxy()()
      vim.api.nvim_buf_delete(0, { force = true })
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "e", "", {
    noremap = true,
    silent = true,
    desc = "Edit",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        local tables = require("kubectl.utils.tables")
        local string_utils = require("kubectl.utils.string")

        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view = require("kubectl.views." .. string.lower(string_utils.trim(buf_name)))
        local ns, name = tables.getCurrentSelection(1, 2)
        if name then
          pcall(view.Edit, name, ns)
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-f>", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      local filter_view = require("kubectl.views.filter")
      filter_view.filter()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-n>", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      local namespace_view = require("kubectl.views.namespace")
      namespace_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "s", "", {
    noremap = false,
    silent = true,
    desc = "Sort",
    callback = function()
      local marks = require("kubectl.utils.marks")
      local state = require("kubectl.state")
      local mark, word = marks.get_current_mark()

      if mark then
        local find = require("kubectl.utils.find")
        local is_header = find.array(state.marks.header, mark[1])
        if is_header then
          state.sortby.mark = mark
          state.sortby.current_word = word
          vim.api.nvim_input("R")
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "1", "", {
    noremap = true,
    silent = true,
    desc = "Deployments",
    callback = function()
      local deployments_view = require("kubectl.views.deployments")
      deployments_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "2", "", {
    noremap = true,
    silent = true,
    desc = "Pods",
    callback = function()
      local pods_view = require("kubectl.views.pods")
      pods_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "3", "", {
    noremap = true,
    silent = true,
    desc = "Configmaps",
    callback = function()
      local configmaps_view = require("kubectl.views.configmaps")
      configmaps_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "4", "", {
    noremap = true,
    silent = true,
    desc = "Secrets",
    callback = function()
      local secrets_view = require("kubectl.views.secrets")
      secrets_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "5", "", {
    noremap = true,
    silent = true,
    desc = "Services",
    callback = function()
      local services_view = require("kubectl.views.services")
      services_view.View()
    end,
  })
end
return M
