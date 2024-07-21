local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local M = {}

--- Register kubectl key mappings
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

  vim.api.nvim_buf_set_keymap(0, "n", "D", "", {
    noremap = true,
    silent = true,
    desc = "Delete",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        local tables = require("kubectl.utils.tables")
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local ns, name = tables.getCurrentSelection(1, 2)
        if name and ns then
          buffers.confirmation_buffer(
            "run - kubectl delete " .. string.lower(buf_name) .. "/" .. name .. " -ns " .. ns,
            "",
            function(confirm)
              if confirm then
                commands.shell_command_async("kubectl", { "delete", buf_name, name, "-n", ns })
              end
            end
          )
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-e>", "", {
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
    noremap = true,
    silent = true,
    desc = "Sort",
    callback = function()
      local marks = require("kubectl.utils.marks")
      local state = require("kubectl.state")
      local find = require("kubectl.utils.find")

      local mark, word = marks.get_current_mark()

      if not mark then
        return
      end

      if not find.array(state.marks.header, mark[1]) then
        return
      end

      local ok, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      if not ok then
        return
      end

      -- TODO: Get the current view in a different way
      buf_name = string.lower(buf_name)
      local sortby = state.sortby[buf_name]

      if not sortby then
        return
      end
      sortby.mark = mark
      sortby.current_word = word

      if state.sortby_old.current_word == sortby.current_word then
        if state.sortby[buf_name].order == "asc" then
          state.sortby[buf_name].order = "desc"
        else
          state.sortby[buf_name].order = "asc"
        end
      end
      state.sortby_old.current_word = sortby.current_word

      vim.api.nvim_input("R")
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
