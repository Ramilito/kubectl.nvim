local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.resources.helm.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = {
    resource = "helm",
    display_name = "Helm",
    ft = "k8s_helm",
    cmd = "helm",
    url = { "ls", "-a", "-A", "--output", "json" },
    hints = {
      { key = "<Plug>(kubectl.kill)", desc = "uninstall" },
      { key = "<Plug>(kubectl.values)", desc = "values" },
    },
    processRow = definition.processRow,
    headers = {
      "NAMESPACE",
      "NAME",
      "REVISION",
      "UPDATED",
      "STATUS",
      "CHART",
      "APP-VERSION",
    },
  },
}

local function add_namespace(args, ns)
  if ns then
    if ns == "All" then
      table.insert(args, "-A")
    else
      table.insert(args, "-n")
      table.insert(args, ns)
    end
  end
  return args
end

local function get_args()
  local ns_filter = state.getNamespace()
  local args = add_namespace({ "ls", "-a", "--output", "json" }, ns_filter)
  return args
end

function M.View(cancellationToken)
  M.definition.url = get_args()
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.buf_nr, builder.win_nr = buffers.buffer(M.definition.ft, builder.resource)
  M.Draw(cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  local sort_data = state.sortby[M.definition.resource]

  if builder then
    commands.shell_command_async(M.definition.cmd, M.definition.url, function(data)
      vim.schedule(function()
        builder.data = data
        builder.decodeJson()

        vim.schedule(function()
          builder.process(M.definition.processRow, true)
          if sort_data then
            builder.sort()
          end
          local windows = buffers.get_windows_by_name(M.definition.resource)
          for _, win_id in ipairs(windows) do
            builder.prettyPrint(win_id).addDivider(true)
            builder.displayContent(win_id, cancellationToken)
          end
          local loop = require("kubectl.utils.loop")
          loop.set_running(builder.buf_nr, false)
        end)
        vim.cmd("doautocmd User K8sDataLoaded")
      end)
    end)
  end
end

-- function M.Desc(name, ns, reload)
--   local builder = manager.get(definition.resource)
--   if not builder then
--     return
--   end
--   builder.view_float({
--     resource = "helm | " .. name .. " | " .. ns,
--     ft = "k8s_desc",
--     url = { "status", name, "-n", ns, "--show-resources" },
--     syntax = "yaml",
--   }, { cmd = definition.cmd, reload = reload })
-- end
--
-- function M.Yaml(name, ns)
--   if name then
--     local def = {
--       resource = "helm" .. " | " .. name,
--       ft = "k8s_yaml",
--       url = { "get", "manifest", name },
--       syntax = "yaml",
--     }
--     if ns then
--       table.insert(def.url, "-n")
--       table.insert(def.url, ns)
--       def.resource = def.resource .. " | " .. ns
--     end
--
--     local builder = manager.get(definition.resource)
--     if not builder then
--       return
--     end
--     builder.view_float(def, { cmd = "helm" })
--   end
-- end
--
-- function M.Values(name, ns)
-- 	vim.print(name, ns)
--   if name then
--     local def = {
--       resource = "helm" .. " | " .. name,
--       ft = "k8s_yaml",
--       url = { "get", "values", name },
--       syntax = "yaml",
--     }
--     if ns then
--       table.insert(def.url, "-n")
--       table.insert(def.url, ns)
--       def.resource = def.resource .. " | " .. ns
--     end
--     local builder = manager.get(definition.resource)
--     if not builder then
--       return
--     end
--     builder.view_float(def, { cmd = "helm" })
--   end
-- end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
