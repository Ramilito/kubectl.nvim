local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local flux_view = require("kubectl.resources.flux")
local mappings = require("kubectl.mappings")

local M = {}

local function build_patch_args(gvk, name, ns, suspend)
  local resource_type = string.lower(gvk.k) .. "." .. gvk.g
  local patch_json = string.format('{"spec":{"suspend":%s}}', suspend and "true" or "false")
  return {
    "patch",
    resource_type,
    name,
    "-n",
    ns,
    "--type=merge",
    "-p",
    patch_json,
  }
end

local function build_reconcile_args(gvk, name, ns)
  local resource_type = string.lower(gvk.k) .. "." .. gvk.g
  local timestamp = tostring(os.time())
  return {
    "annotate",
    resource_type,
    name,
    "-n",
    ns,
    "reconcile.fluxcd.io/requestedAt=" .. timestamp,
    "--overwrite",
  }
end

M.overrides = {
  ["<Plug>(kubectl.flux_suspend)"] = {
    noremap = true,
    silent = true,
    desc = "Suspend Flux resource",
    callback = function()
      local name, ns = flux_view.getCurrentSelection()
      local gvk = flux_view._get_current_row_gvk()
      if not name or not gvk then
        return
      end
      buffers.confirmation_buffer(
        string.format("Suspend %s: %s in namespace %s?", gvk.k, name, ns),
        "prompt",
        function(confirm)
          if confirm then
            local args = build_patch_args(gvk, name, ns, true)
            commands.shell_command_async("kubectl", args, function(response)
              vim.schedule(function()
                vim.notify(response)
              end)
            end)
          end
        end
      )
    end,
  },

  ["<Plug>(kubectl.flux_resume)"] = {
    noremap = true,
    silent = true,
    desc = "Resume Flux resource",
    callback = function()
      local name, ns = flux_view.getCurrentSelection()
      local gvk = flux_view._get_current_row_gvk()
      if not name or not gvk then
        return
      end
      local args = build_patch_args(gvk, name, ns, false)
      commands.shell_command_async("kubectl", args, function(response)
        vim.schedule(function()
          vim.notify(response)
        end)
      end)
    end,
  },

  ["<Plug>(kubectl.flux_reconcile)"] = {
    noremap = true,
    silent = true,
    desc = "Force reconcile Flux resource",
    callback = function()
      local name, ns = flux_view.getCurrentSelection()
      local gvk = flux_view._get_current_row_gvk()
      if not name or not gvk then
        return
      end
      buffers.confirmation_buffer(
        string.format("Force reconcile %s: %s in namespace %s?", gvk.k, name, ns),
        "prompt",
        function(confirm)
          if confirm then
            local args = build_reconcile_args(gvk, name, ns)
            commands.shell_command_async("kubectl", args, function(response)
              vim.schedule(function()
                vim.notify(response)
              end)
            end)
          end
        end
      )
    end,
  },

  ["<Plug>(kubectl.describe)"] = {
    noremap = true,
    silent = true,
    desc = "Describe Flux resource",
    callback = function()
      local name, ns = flux_view.getCurrentSelection()
      if name then
        flux_view.Desc(name, ns)
      end
    end,
  },

  ["<Plug>(kubectl.yaml)"] = {
    noremap = true,
    silent = true,
    desc = "View YAML",
    callback = function()
      local name, ns = flux_view.getCurrentSelection()
      if name then
        flux_view.Yaml(name, ns)
      end
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gs", "<Plug>(kubectl.flux_suspend)")
  mappings.map_if_plug_not_set("n", "gS", "<Plug>(kubectl.flux_resume)")
  mappings.map_if_plug_not_set("n", "gR", "<Plug>(kubectl.flux_reconcile)")
  mappings.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.describe)")
  mappings.map_if_plug_not_set("n", "gy", "<Plug>(kubectl.yaml)")
end

return M
