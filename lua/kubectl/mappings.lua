local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local views = require("kubectl.views")
local M = {}

local function is_plug_mapped(plug_target, mode)
  local mappings = vim.api.nvim_get_keymap(mode)
  for _, mapping in ipairs(mappings) do
    if mapping.rhs == plug_target then
      return true
    end
  end
  return false
end

function M.map_if_plug_not_set(mode, lhs, plug_target, opts)
  if not is_plug_mapped(plug_target, mode) then
    vim.api.nvim_set_keymap("n", lhs, plug_target, opts or { noremap = true, silent = true, callback = nil })
  end
end

--- Register kubectl key mappings
function M.register()
  -- Global mappings
  M.map_if_plug_not_set("n", "1", "<Plug>(kubectl.view_1)")
  M.map_if_plug_not_set("n", "2", "<Plug>(kubectl.view_2)")
  M.map_if_plug_not_set("n", "3", "<Plug>(kubectl.view_3)")
  M.map_if_plug_not_set("n", "4", "<Plug>(kubectl.view_4)")
  M.map_if_plug_not_set("n", "5", "<Plug>(kubectl.view_5)")
  M.map_if_plug_not_set("n", "<C-a>", "<Plug>(kubectl.alias_view)")
  M.map_if_plug_not_set("n", "<C-f>", "<Plug>(kubectl.filter_view)")
  M.map_if_plug_not_set("n", "<C-n>", "<Plug>(kubectl.namespace_view)")
  M.map_if_plug_not_set("n", "<bs>", "<Plug>(kubectl.go_up)")
  M.map_if_plug_not_set("n", "<cr>", "<Plug>(kubectl.select)")
  M.map_if_plug_not_set("n", "gP", "<Plug>(kubectl.portforwards_view)")
  M.map_if_plug_not_set("n", "g?", "<Plug>(kubectl.help)")
  M.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
  M.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.describe)")
  M.map_if_plug_not_set("n", "ge", "<Plug>(kubectl.edit)")
  M.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
  M.map_if_plug_not_set("n", "gs", "<Plug>(kubectl.sort)")

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.portforwards_view)", "", {
    noremap = true,
    silent = true,
    desc = "View Port Forwards",
    callback = function()
      views.PortForwards()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.delete)", "", {
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

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.describe)", "", {
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

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.refresh)", "", {
    noremap = true,
    silent = true,
    desc = "Reload",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative == "" then
        local string_utils = require("kubectl.utils.string")

        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        vim.notify("Reloading " .. buf_name, vim.log.levels.INFO)
        local ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(buf_name)))
        if ok then
          pcall(view.View)
        else
          view = require("kubectl.views.fallback")
          view.View()
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.edit)", "", {
    noremap = true,
    silent = true,
    desc = "Edit resource",
    callback = function()
      local win_config = vim.api.nvim_win_get_config(0)
      if win_config.relative ~= "" then
        return
      end

      -- Retrieve buffer name and load the appropriate view
      local string_utils = require("kubectl.utils.string")
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end

      -- Get resource details and construct the kubectl command
      local resource = view.builder.resource
      local name, ns = view.getCurrentSelection()

      if not name then
        vim.notify("Not a valid selection to edit", vim.log.levels.INFO)
        return
      end

      local args = { "get", resource .. "/" .. name, "-o", "yaml" }
      if ns and ns ~= "nil" then
        table.insert(args, "-n")
        table.insert(args, ns)
      end

      -- Save the resource data to a temporary file
      local self = ResourceBuilder:new("edit_resource"):setCmd(args, "kubectl"):fetch()

      local tmpfilename = string.format("%s-%s-%s.yaml", vim.fn.tempname(), name, ns)
      vim.print("editing " .. tmpfilename)

      local tmpfile = assert(io.open(tmpfilename, "w+"), "Failed to open temp file")
      tmpfile:write(self.data)
      tmpfile:close()

      local original_mtime = vim.loop.fs_stat(tmpfilename).mtime.sec
      vim.api.nvim_buf_set_var(0, "original_mtime", original_mtime)

      -- open the file
      vim.cmd("tabnew | edit " .. tmpfilename)

      vim.api.nvim_buf_set_option(0, "bufhidden", "wipe")
      local group = vim.api.nvim_create_augroup("__kubectl_edited", { clear = false })

      vim.api.nvim_create_autocmd("QuitPre", {
        buffer = 0,
        group = group,
        callback = function()
          -- Defer action to let :wq have time to modify file
          vim.defer_fn(function()
            ---@diagnostic disable-next-line: redefined-local
            local ok, original_mtime = pcall(vim.api.nvim_buf_get_var, 0, "original_mtime")
            local current_mtime = vim.loop.fs_stat(tmpfilename).mtime.sec

            if ok and current_mtime ~= original_mtime then
              vim.notify("Edited. Applying changes")
              commands.shell_command_async("kubectl", { "apply", "-f", tmpfilename }, function(apply_data)
                vim.schedule(function()
                  vim.notify(apply_data, vim.log.levels.INFO)
                end)
              end)
            else
              vim.notify("Not Edited", vim.log.levels.INFO)
            end
          end, 100)
        end,
      })
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.alias_view)", "", {
    noremap = true,
    silent = true,
    desc = "Aliases",
    callback = function()
      local view = require("kubectl.views")
      view.Aliases()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.filter_view)", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      local filter_view = require("kubectl.views.filter")
      filter_view.filter()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.namespace_view)", "", {
    noremap = true,
    silent = true,
    desc = "Change namespace",
    callback = function()
      local namespace_view = require("kubectl.views.namespace")
      namespace_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.sort)", "", {
    noremap = true,
    silent = true,
    desc = "Sort",
    callback = function()
      local marks = require("kubectl.utils.marks")
      local state = require("kubectl.state")
      local find = require("kubectl.utils.find")

      local mark, word = marks.get_current_mark(state.content_row_start)

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

      local string_utils = require("kubectl.utils.string")
      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end
      pcall(view.Draw)
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.view_1)", "", {
    noremap = true,
    silent = true,
    desc = "Deployments",
    callback = function()
      local view = require("kubectl.views.deployments")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.view_2)", "", {
    noremap = true,
    silent = true,
    desc = "Pods",
    callback = function()
      local view = require("kubectl.views.pods")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.view_3)", "", {
    noremap = true,
    silent = true,
    desc = "Configmaps",
    callback = function()
      local view = require("kubectl.views.configmaps")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.view_4)", "", {
    noremap = true,
    silent = true,
    desc = "Secrets",
    callback = function()
      local view = require("kubectl.views.secrets")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.view_5)", "", {
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
