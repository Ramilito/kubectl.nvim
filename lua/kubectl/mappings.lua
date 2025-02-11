local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local event_handler = require("kubectl.actions.eventhandler").handler
local string_utils = require("kubectl.utils.string")
local viewsTable = require("kubectl.utils.viewsTable")
local M = {}

local function is_plug_mapped(plug_target, mode)
  if vim.fn.hasmapto(plug_target, mode) == 1 then
    return true
  end
  return false
end

function M.map_if_plug_not_set(mode, lhs, plug_target, opts)
  if not is_plug_mapped(plug_target, mode) then
    vim.api.nvim_buf_set_keymap(0, mode, lhs, plug_target, opts or { noremap = true, silent = true, callback = nil })
  end
end

function M.get_mappings()
  local win_id = vim.api.nvim_get_current_win()
  local win_config = vim.api.nvim_win_get_config(win_id)

  local mappings = {
    ["<Plug>(kubectl.portforwards_view)"] = {
      mode = "n",
      desc = "View Port Forwards",
      callback = function()
        local view = require("kubectl.views")
        view.PortForwards()
      end,
    },
    ["<Plug>(kubectl.go_up)"] = {
      mode = "n",
      desc = "Go up",
      callback = function()
        local view = require("kubectl.views")
        local state = require("kubectl.state")
        local older_view = state.history[#state.history - 1]
        if not older_view then
          return
        end
        table.remove(state.history, #state.history)
        view.view_or_fallback(older_view)
      end,
    },
    ["<Plug>(kubectl.help)"] = {
      mode = "n",
      desc = "Help",
      callback = function()
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view = require("kubectl.views")
        local _, definition = view.view_and_definition(string.lower(vim.trim(buf_name)))

        if definition then
          view.Hints(definition.hints)
        end
      end,
    },
    ["<Plug>(kubectl.delete)"] = {
      mode = "n",
      desc = "Delete",
      callback = function()
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end
        local tables = require("kubectl.utils.tables")
        local state = require("kubectl.state")
        local selections = state.getSelections()
        if vim.tbl_count(selections) == 0 then
          local name, ns = view.getCurrentSelection()
          if name then
            selections = { { name = name, namespace = ns } }
          end
        end

        local data = {}
        for _, value in ipairs(selections) do
          table.insert(data, { name = value.name, namespace = value.namespace })
        end

        local self = ResourceBuilder:new("delete_resource")
        self.data = data
        self.processedData = self.data

        local prompt = "Are you sure you want to delete the selected resource(s)?"
        local buf_nr, win = buffers.confirmation_buffer(prompt, "prompt", function(confirm)
          if confirm then
            local resource = string.lower(buf_name)
            for _, selection in ipairs(selections) do
              local name = selection.name
              local ns = selection.namespace
              vim.notify("deleting " .. name)
              if name then
                if buf_name == "fallback" then
                  resource = view.resource
                end
                local args = { "delete", resource, name }
                if ns and ns ~= "nil" then
                  table.insert(args, "-n")
                  table.insert(args, ns)
                end
                commands.shell_command_async("kubectl", args, function(delete_data)
                  vim.schedule(function()
                    vim.notify(delete_data, vim.log.levels.INFO)
                  end)
                end)
              end
            end
            state.selections = {}
            vim.schedule(function()
              view.Draw()
            end)
          end
        end)

        self.buf_nr = buf_nr
        self.prettyData, self.extmarks = tables.pretty_print(self.processedData, { "NAME", "NAMESPACE" })

        table.insert(self.prettyData, "")
        table.insert(self.prettyData, "")
        local confirmation = "[y]es [n]o"
        local padding = string.rep(" ", (win.width - #confirmation) / 2)
        table.insert(self.extmarks, {
          row = #self.prettyData - 1,
          start_col = 0,
          virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
          virt_text_pos = "inline",
        })
        self:setContent()
      end,
    },
    ["<Plug>(kubectl.yaml)"] = {
      mode = "n",
      desc = "View yaml",
      callback = function()
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end
        local name, ns = view.getCurrentSelection()

        if name then
          if buf_name == "helm" then
            local helm_view = require("kubectl.views.helm")
            helm_view.Yaml(name, ns)
          else
            local def = {
              resource = buf_name .. " | " .. name,
              ft = "k8s_yaml",
              url = { "get", buf_name, name, "-o", "yaml" },
              syntax = "yaml",
            }
            if ns then
              table.insert(def.url, "-n")
              table.insert(def.url, ns)
              def.resource = def.resource .. " | " .. ns
            end

            ResourceBuilder:view_float(def, { cmd = "kubectl" })
          end
        end
      end,
    },
    ["<Plug>(kubectl.describe)"] = {
      mode = "n",
      desc = "Describe resource",
      callback = function()
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end
        local name, ns = view.getCurrentSelection()
        if name then
          local ok = pcall(view.Desc, name, ns, true)
          vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.refresh)", "", {
            noremap = true,
            silent = true,
            desc = "Refresh",
            callback = function()
              vim.schedule(function()
                pcall(view.Desc, name, ns, false)
              end)
            end,
          })
          vim.schedule(function()
            M.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
          end)
          if ok then
            local state = require("kubectl.state")
            event_handler:on("MODIFIED", state.instance_float.buf_nr, function(event)
              if event.object.metadata.name == name and event.object.metadata.namespace == ns then
                vim.schedule(function()
                  pcall(view.Desc, name, ns, false)
                end)
              end
            end)
          else
            vim.api.nvim_err_writeln("Failed to describe " .. buf_name .. ".")
          end
        end
      end,
    },
    ["<Plug>(kubectl.refresh)"] = {
      mode = "n",
      desc = "Reload",
      callback = function()
        if win_config.relative == "" then
          local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
          vim.notify("Reloading " .. buf_name, vim.log.levels.INFO)
          local ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
          if ok then
            pcall(view.View)
          else
            view = require("kubectl.views.fallback")
            view.View()
          end
        else
          local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
          local resource = vim.split(buf_name, "_")
          local ok, view = pcall(require, "kubectl.views." .. resource[1])

          if not ok then
            view = require("kubectl.views.fallback")
          end
          pcall(view[string_utils.capitalize(resource[2])], resource[3] or "", resource[4] or "")
        end
      end,
    },
    ["<Plug>(kubectl.edit)"] = {
      mode = "n",
      desc = "Edit resource",
      callback = function()
        local state = require("kubectl.state")

        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end

        local resource = state.instance.resource
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

        local self = ResourceBuilder:new("edit_resource"):setCmd(args, "kubectl"):fetch()

        local tmpfilename = string.format("%s-%s-%s.yaml", vim.fn.tempname(), name, ns)
        vim.print("editing " .. tmpfilename)

        local tmpfile = assert(io.open(tmpfilename, "w+"), "Failed to open temp file")
        tmpfile:write(self.data)
        tmpfile:close()

        local original_mtime = vim.loop.fs_stat(tmpfilename).mtime.sec
        vim.api.nvim_buf_set_var(0, "original_mtime", original_mtime)

        vim.cmd("tabnew | edit " .. tmpfilename)

        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = 0 })
        local group = vim.api.nvim_create_augroup("__kubectl_edited", { clear = false })

        vim.api.nvim_create_autocmd("QuitPre", {
          buffer = 0,
          group = group,
          callback = function()
            vim.defer_fn(function()
              local ok
              ok, original_mtime = pcall(vim.api.nvim_buf_get_var, 0, "original_mtime")
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
    },
    ["<Plug>(kubectl.toggle_headers)"] = {
      mode = "n",
      desc = "Toggle headers",
      callback = function()
        config.options.headers = not config.options.headers
        pcall(require("kubectl.views").Redraw)
      end,
    },
    ["<Plug>(kubectl.alias_view)"] = {
      mode = "n",
      desc = "Aliases",
      callback = function()
        local view = require("kubectl.views")
        view.Aliases()
      end,
    },
    ["<Plug>(kubectl.filter_view)"] = {
      mode = "n",
      desc = "Filter",
      callback = function()
        local filter_view = require("kubectl.views.filter")
        filter_view.filter()
      end,
    },
    ["<Plug>(kubectl.picker_view)"] = {
      mode = "n",
      desc = "Picker",
      callback = function()
        local view = require("kubectl.views")
        view.Picker()
      end,
    },
    ["<Plug>(kubectl.filter_term)"] = {
      mode = "v",
      desc = "Filter",
      callback = function()
        local filter_view = require("kubectl.views.filter")
        local state = require("kubectl.state")
        local filter_term = string_utils.get_visual_selection()
        if not filter_term then
          return
        end
        filter_view.save_history(filter_term)
        state.setFilter(filter_term)

        vim.api.nvim_set_option_value("modified", false, { buf = 0 })
        vim.notify("filtering for.. " .. filter_term)
        vim.api.nvim_input("<Plug>(kubectl.refresh)")
      end,
    },
    ["<Plug>(kubectl.filter_label)"] = {
      mode = "n",
      desc = "Filter",
      callback = function()
        local filter_view = require("kubectl.views.filter")
        filter_view.filter_label()
      end,
    },
    ["<Plug>(kubectl.namespace_view)"] = {
      mode = "n",
      desc = "Change namespace",
      callback = function()
        local namespace_view = require("kubectl.views.namespace")
        namespace_view.View()
      end,
    },
    ["<Plug>(kubectl.contexts_view)"] = {
      mode = "n",
      desc = "Change context",
      callback = function()
        local contexts_view = require("kubectl.views.contexts")
        contexts_view.View()
      end,
    },
    ["<Plug>(kubectl.sort)"] = {
      mode = "n",
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

        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end
        pcall(view.Draw)
      end,
    },
    ["<Plug>(kubectl.quit)"] = {
      mode = "n",
      desc = "Close buffer",
      callback = function()
        vim.api.nvim_set_option_value("modified", false, { buf = 0 })
        vim.cmd.close()
      end,
    },
    ["<Plug>(kubectl.tab)"] = {
      mode = "n",
      desc = "Select resource",
      callback = function()
        local state = require("kubectl.state")
        local view = require("kubectl.views")
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local current_view, _ = view.view_and_definition(string.lower(vim.trim(buf_name)))

        local name, ns = current_view.getCurrentSelection()
        for i, selection in ipairs(state.selections) do
          if selection.name == name and (ns and selection.namespace == ns or true) then
            table.remove(state.selections, i)
            vim.api.nvim_feedkeys("j", "n", true)
            current_view.Draw()
            return
          end
        end

        if name then
          table.insert(state.selections, { name = name, namespace = ns })
          vim.api.nvim_feedkeys("j", "n", true)
          current_view.Draw()
        end
      end,
    },
  }

  -- Add dynamic "view" mappings
  for _, view_name in ipairs(vim.tbl_keys(viewsTable)) do
    local keymap_name = string.gsub(view_name, "-", "_")
    local desc = string_utils.capitalize(view_name) .. " view"

    mappings["<Plug>(kubectl.view_" .. keymap_name .. ")"] = {
      mode = "n",
      desc = desc,
      callback = function()
        local view = require("kubectl.views." .. view_name)
        view.View()
      end,
    }
  end

  return mappings
end

--- Register kubectl key mappings
function M.register()
  local win_id = vim.api.nvim_get_current_win()
  local win_config = vim.api.nvim_win_get_config(win_id)
  -- Global mappings
  if win_config.relative == "" then
    M.map_if_plug_not_set("n", "1", "<Plug>(kubectl.view_deployments)")
    M.map_if_plug_not_set("n", "2", "<Plug>(kubectl.view_pods)")
    M.map_if_plug_not_set("n", "3", "<Plug>(kubectl.view_configmaps)")
    M.map_if_plug_not_set("n", "4", "<Plug>(kubectl.view_secrets)")
    M.map_if_plug_not_set("n", "5", "<Plug>(kubectl.view_services)")
    M.map_if_plug_not_set("n", "6", "<Plug>(kubectl.view_ingresses)")
    M.map_if_plug_not_set("n", "<bs>", "<Plug>(kubectl.go_up)")
    M.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
    M.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.describe)")
    M.map_if_plug_not_set("n", "gy", "<Plug>(kubectl.yaml)")
    M.map_if_plug_not_set("n", "ge", "<Plug>(kubectl.edit)")
    M.map_if_plug_not_set("n", "gs", "<Plug>(kubectl.sort)")
    M.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
    M.map_if_plug_not_set("n", "<M-h>", "<Plug>(kubectl.toggle_headers)")
  else
    local opts = { noremap = true, silent = true, callback = nil }
    vim.api.nvim_buf_set_keymap(0, "n", "q", "<Plug>(kubectl.quit)", opts)
    vim.api.nvim_buf_set_keymap(0, "n", "<esc>", "<Plug>(kubectl.quit)", opts)
    vim.api.nvim_buf_set_keymap(0, "i", "<C-c>", "<Esc><Plug>(kubectl.quit)", opts)
  end

  M.map_if_plug_not_set("n", "gP", "<Plug>(kubectl.portforwards_view)")
  M.map_if_plug_not_set("n", "<C-a>", "<Plug>(kubectl.alias_view)")
  M.map_if_plug_not_set("n", "<C-f>", "<Plug>(kubectl.filter_view)")
  M.map_if_plug_not_set("v", "<C-f>", "<Plug>(kubectl.filter_term)")
  M.map_if_plug_not_set("n", "<C-l>", "<Plug>(kubectl.filter_label)")
  M.map_if_plug_not_set("n", "<C-p>", "<Plug>(kubectl.picker_view)")
  M.map_if_plug_not_set("n", "<C-n>", "<Plug>(kubectl.namespace_view)")
  M.map_if_plug_not_set("n", "<C-x>", "<Plug>(kubectl.contexts_view)")
  M.map_if_plug_not_set("n", "g?", "<Plug>(kubectl.help)")
  M.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
  M.map_if_plug_not_set("n", "<cr>", "<Plug>(kubectl.select)")

  if config.options.lineage.enabled then
    M.map_if_plug_not_set("n", "gx", "<Plug>(kubectl.lineage)")
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("Kubectl", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "k8s_*",
    callback = function(ev)
      local view_name = ev.match:gsub("k8s_", "")
      local ok, view_mappings = pcall(require, "kubectl.views." .. view_name .. ".mappings")

      vim.print(ev)
      local globals = M.get_mappings()
      local locals = {}
      if ok then
        locals = view_mappings.overrides
      end

      local all_mappings = vim.tbl_deep_extend("force", globals, locals)
      for lhs, def in pairs(all_mappings) do
        vim.keymap.set(def.mode or "n", lhs, def.callback, {
          desc = def.desc,
          noremap = def.noremap ~= false,
          silent = def.silent ~= false,
          buffer = true,
        })
      end

      if ok then
        view_mappings.register()
      end
      M.register()
    end,
  })
end
return M
