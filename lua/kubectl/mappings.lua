local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local views = require("kubectl.views")
local M = {}

--- Register kubectl key mappings
function M.register()
  local config = require("kubectl.config")
  local km = config.options.keymaps
  local gl = km.global
  local vw = km.views
  vim.api.nvim_buf_set_keymap(0, "n", gl.view_pfs.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.view_pfs),
    callback = function()
      views.PortForwards()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", gl.delete.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.delete),
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

  vim.api.nvim_buf_set_keymap(0, "n", gl.describe.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.describe),
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

  vim.api.nvim_buf_set_keymap(0, "n", gl.reload.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.reload),
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

  vim.api.nvim_buf_set_keymap(0, "n", gl.edit.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.edit),
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

  vim.api.nvim_buf_set_keymap(0, "n", gl.aliases.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.aliases),
    callback = function()
      local view = require("kubectl.views")
      view.Aliases()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", gl.filter.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.filter),
    callback = function()
      local filter_view = require("kubectl.views.filter")
      filter_view.filter()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", gl.namespaces.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.namespaces),
    callback = function()
      local namespace_view = require("kubectl.views.namespace")
      namespace_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", gl.sort.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.sort),
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

  vim.api.nvim_buf_set_keymap(0, "n", vw.deployments.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(vw.deployments),
    callback = function()
      local view = require("kubectl.views.deployments")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", vw.pods.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(vw.pods),
    callback = function()
      local view = require("kubectl.views.pods")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", vw.configmaps.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(vw.configmaps),
    callback = function()
      local view = require("kubectl.views.configmaps")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", vw.secrets.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(vw.secrets),
    callback = function()
      local view = require("kubectl.views.secrets")
      view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", vw.services.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(vw.services),
    callback = function()
      local view = require("kubectl.views.services")
      view.View()
    end,
  })
end
return M
