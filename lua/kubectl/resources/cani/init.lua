local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local hl = require("kubectl.actions.highlight")

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
      "NAME",
      "API-GROUP",
      "GET",
      "LIST",
      "WATCH",
      "CREATE",
      "PATCH",
      "UPDATE",
      "DELETE",
      "DEL-LIST",
      "EXTRAS",
    },
  },
}

local function verb_symbol(enabled)
  if enabled then
    return { value = "", symbol = hl.symbols.success }
  else
    return { value = "", symbol = "" }
  end
end

---@param rows table
---@return table
local function processRow(rows)
  local data = {}
  if not rows then
    return data
  end
  for _, row in ipairs(rows) do
    table.insert(data, {
      name = { value = row.name or "", symbol = "" },
      ["api-group"] = { value = row.api_group or "", symbol = "" },
      get = verb_symbol(row.get),
      list = verb_symbol(row.list),
      watch = verb_symbol(row.watch),
      create = verb_symbol(row.create),
      patch = verb_symbol(row.patch),
      update = verb_symbol(row.update),
      delete = verb_symbol(row.delete),
      ["del-list"] = verb_symbol(row.del_list),
      extras = { value = row.extras or "", symbol = "" },
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
