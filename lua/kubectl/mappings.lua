local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local manager = require("kubectl.resource_manager")
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
        local builder = manager.get_or_create("delete_view")

        local def = {
          resource = "delete_resource",
          display = "Delete resource",
          ft = "k8s_action",
          group = view.definition.group,
          version = view.definition.version,
        }

        local action_data = {}
        for _, value in ipairs(selections) do
          local ns_prefix = value.namespace and (value.namespace .. ": ") or ""
          table.insert(action_data, {
            text = ">> " .. ns_prefix .. value.name,
            value = "",
            cmd = { name = value.name, namespace = value.namespace },
            type = "positional",
          })
        end
        builder.data = data
        builder.action_view(def, action_data, function(args)
          local gvk = view.definition.gvk
          for _, value in ipairs(args) do
            local ns = value.cmd.namespace
            local name = value.cmd.name

            vim.notify("Deleting " .. gvk.k .. ": " .. name, vim.log.levels.INFO)
            commands.run_async("delete_async", { gvk = gvk, namespace = ns, name = name }, function(_, err)
              vim.schedule(function()
                if not err then
                  vim.notify(gvk.k .. " deleted: " .. name, vim.log.levels.INFO)
                end
              end)
            end)
          end
          state.selections = {}
        end)
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
              resource = view.definition.resource,
              gvk = view.definition.gvk,
              display_name = string.upper(view.definition.resource),
              ft = "k8s_yaml",
              syntax = "yaml",
              cmd = "get_single_async",
            }
            if ns then
              def.display_name = def.display_name .. " | " .. ns
            end

            local builder = manager.get_or_create("yaml")
            builder.view_float(def, {
              args = {
                def.gvk.k,
                ns,
                name,
                "yaml",
              },
            })
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
          view.Desc(name, ns, true)
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
          ---@type string[] @Expected format: "resource_operation_name_namespace"
          -- `operation`: string, the operation type
          -- `kind`: string, the resource type
          -- `name`: string|nil, the resource name
          -- `ns`: string|nil, the namespace
          local parts = vim.split(buf_name, "|")

          vim.notify("Reloading " .. parts[3], vim.log.levels.INFO)
          local ok, view = pcall(require, "kubectl.views." .. vim.trim(parts[2]))

          if not ok then
            vim.notify(parts[3] .. " not found", vim.log.levels.INFO)
            return
          end

          local operation = vim.trim(parts[1]:gsub("k8s_", ""))
          local name = vim.trim(parts[3] or "")
          local namespace = vim.trim(parts[4] or "")

          local func = view[string_utils.capitalize(operation)]
          if operation == "desc" then
            pcall(func, name, namespace, false)
          elseif operation == "yaml" then
            vim.api.nvim_input("<Plug>(kubectl.yaml)")
          else
            assert(type(func) == "function", "Expected a function for key: " .. string_utils.capitalize(operation))
            pcall(func, name, namespace)
          end
        end
      end,
    },
    ["<Plug>(kubectl.edit)"] = {
      mode = "n",
      desc = "Edit resource",
      callback = function()
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if not view_ok then
          view = require("kubectl.views.fallback")
        end

        local name, ns = view.getCurrentSelection()

        if not name then
          vim.notify("Not a valid selection to edit", vim.log.levels.INFO)
          return
        end

        local instance = manager.get(buf_name)
        if not instance then
          vim.notify("Resource not found", vim.log.levels.INFO)
          return
        end
        local def = {
          resource = buf_name .. " | " .. name,
          syntax = "yaml",
          resource_name = string_utils.capitalize(instance.definition.resource_name),
          name = name,
          ns = ns,
          gvk = instance.definition.gvk,
          group = instance.definition.group,
          version = instance.definition.version,
        }
        commands.run_async("fetch_async", {
          gvk = def.gvk,
          name = def.name,
          namespace = def.ns,
          output = "Yaml",
        }, function(data)
          vim.schedule(function()
            local tmpfilename = string.format("%s-%s-%s.yaml", vim.fn.tempname(), name, ns)

            local tmpfile = assert(io.open(tmpfilename, "w+"), "Failed to open temp file")
            tmpfile:write(data)
            tmpfile:close()

            vim.cmd("tabnew | edit " .. tmpfilename)

            vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = 0 })
            local group = vim.api.nvim_create_augroup("__kubectl_edited", { clear = false })

            vim.api.nvim_create_autocmd("QuitPre", {
              buffer = 0,
              group = group,
              callback = function()
                commands.run_async("edit_async", {
                  tmpfilename,
                }, function(result, err)
                  vim.schedule(function()
                    vim.notify(result or err)
                  end)
                end)
              end,
            })
          end)
        end)
      end,
    },
    ["<Plug>(kubectl.toggle_headers)"] = {
      mode = "n",
      desc = "Toggle headers",
      callback = function()
        config.options.headers.enabled = not config.options.headers.enabled
        if not config.options.headers.enabled then
          local bufnr = buffers.get_buffer_by_name("kubectl_header")
          if bufnr then
            vim.api.nvim_buf_delete(bufnr, { force = true })
            manager.remove("header")
          end
        else
          pcall(require("kubectl.views").Header)
        end
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
    ["<Plug>(kubectl.lineage)"] = {
      noremap = true,
      silent = true,
      desc = "Application lineage",
      callback = function()
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        local view = require("kubectl.views")
        local current_view, _ = view.view_and_definition(string.lower(vim.trim(buf_name)))

        local name, ns = current_view.getCurrentSelection()
        local lineage_view = require("kubectl.views.lineage")

        lineage_view.View(name, ns, current_view.definition.gvk.k)
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
    M.map_if_plug_not_set("n", "gxx", "<Plug>(kubectl.lineage)")
  end
end

function M.setup(ev)
  local view_name = ev.match:gsub("k8s_", "")
  local ok, view_mappings = pcall(require, "kubectl.views." .. view_name .. ".mappings")

  local globals = M.get_mappings()
  local locals = {}
  if ok and view_mappings.overrides then
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
    pcall(view_mappings.register)
  end
  M.register()
end
return M
