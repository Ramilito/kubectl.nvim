local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = {
    resource = "cani",
    display_name = "CAN-I",
    ft = "k8s_cani",
    auto_refresh = false,
    hints = {
      { key = "<Plug>(kubectl.refresh)", desc = "refresh" },
    },
    headers = {
      "RESOURCES",
      "API GROUPS",
      "VERBS",
      "RESOURCE NAMES",
      "NON-RESOURCE URLS",
    },
  },
}

---@param rows table
---@return table
local function processRow(rows)
  local data = {}
  if not rows then
    return data
  end
  for _, row in ipairs(rows) do
    table.insert(data, {
      resources = { value = row.resources or "", symbol = "" },
      api_groups = { value = row.api_groups or "", symbol = "" },
      verbs = { value = row.verbs or "", symbol = "" },
      resource_names = { value = row.resource_names or "", symbol = "" },
      non_resource_urls = { value = row.non_resource_urls or "", symbol = "" },
    })
  end
  return data
end

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.buf_nr, builder.win_nr = buffers.buffer(M.definition.ft, builder.resource)
  M.Draw(cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  local sort_data = state.sortby[M.definition.resource]
  local ns = state.getNamespace()
  if ns == "All" then
    ns = "default"
  end

  if builder then
    commands.run_async("get_self_subject_rules_async", { namespace = ns }, function(data)
      vim.schedule(function()
        builder.data = data
        builder.decodeJson()

        vim.schedule(function()
          builder.process(processRow, true)
          if sort_data then
            builder.sort()
          end
          local windows = buffers.get_windows_by_name(M.definition.resource)
          for _, win_id in ipairs(windows) do
            builder.prettyPrint(win_id).addDivider(true)
            builder.displayContent(win_id, cancellationToken)
          end
        end)
        vim.cmd("doautocmd User K8sDataLoaded")
      end)
    end)
  end
end

---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
