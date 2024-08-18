local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local views = require("kubectl.views")
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
      local ok, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      if ok then
        commands.save_config("kubectl.session.json", { view = buf_name })
      end

      -- Only stop proxy if not a floating buffer
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        kube.stop_kubectl_proxy()()
      end
      vim.api.nvim_buf_delete(0, { force = true })
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "gP", "", {
    noremap = true,
    silent = true,
    desc = "View Port Forwards",
    callback = function()
      views.PortForwards()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "gD", "", {
    noremap = true,
    silent = true,
    desc = "Delete",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative ~= "" then
        return
      end
      local string_utils = require("kubectl.utils.string")
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view = require("kubectl.views." .. string.lower(string_utils.trim(buf_name)))

      local name, ns = view.getCurrentSelection()
      if name then
        local resource = string.lower(buf_name)
        if buf_name == "fallback" then
          resource = view.resource
        end
        local args = { "delete", resource, name }
        if ns and ns ~= "nil" then
          table.insert(args, "-n")
          table.insert(args, ns)
        end
        buffers.confirmation_buffer("execute: kubectl " .. table.concat(args, " "), "", function(confirm)
          if confirm then
            commands.shell_command_async("kubectl", args)
          end
        end)
      end
    end,
  })
  vim.api.nvim_buf_set_keymap(0, "n", "gd", "", {
    noremap = true,
    silent = true,
    desc = "Describe resource",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        local string_utils = require("kubectl.utils.string")

        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end
        local name, ns = view.getCurrentSelection()
        if name then
          local ok = pcall(view.Desc, name, ns)
          if not ok then
            vim.api.nvim_err_writeln("Failed to describe " .. buf_name .. ".")
          end
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "gr", "", {
    noremap = true,
    silent = true,
    desc = "Reload",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        local string_utils = require("kubectl.utils.string")

        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(buf_name)))
        if ok then
          vim.notify("Reloading " .. buf_name, vim.log.levels.INFO)
          pcall(view.View)
        else
          view = require("kubectl.views.fallback")
          view.View()
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "ge", "", {
    noremap = true,
    silent = true,
    desc = "Edit resource",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        local string_utils = require("kubectl.utils.string")

        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view = require("kubectl.views." .. string.lower(string_utils.trim(buf_name)))
        local name, ns = view.getCurrentSelection()
        if name then
          pcall(view.Edit, name, ns)
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-a>", "", {
    noremap = true,
    silent = true,
    desc = "Aliases",
    callback = function()
      local view = require("kubectl.views")
      view.Aliases()
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
    desc = "Change namespace",
    callback = function()
      local namespace_view = require("kubectl.views.namespace")
      namespace_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "gs", "", {
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

      vim.api.nvim_input("gr")
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "0", "", {
    noremap = true,
    silent = true,
    desc = "Root",
    callback = function()
      local view = require("kubectl.views.root")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "1", "", {
    noremap = true,
    silent = true,
    desc = "Deployments",
    callback = function()
      local view = require("kubectl.views.deployments")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "2", "", {
    noremap = true,
    silent = true,
    desc = "Pods",
    callback = function()
      local view = require("kubectl.views.pods")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "3", "", {
    noremap = true,
    silent = true,
    desc = "Configmaps",
    callback = function()
      local view = require("kubectl.views.configmaps")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "4", "", {
    noremap = true,
    silent = true,
    desc = "Secrets",
    callback = function()
      local view = require("kubectl.views.secrets")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "5", "", {
    noremap = true,
    silent = true,
    desc = "Services",
    callback = function()
      local view = require("kubectl.views.services")
      view.View()
    end,
  })
end
return M
