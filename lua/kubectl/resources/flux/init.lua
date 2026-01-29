local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.resources.flux.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = {
    resource = "flux",
    display_name = "Flux",
    ft = "k8s_flux",
    hints = {
      { key = "<Plug>(kubectl.flux_suspend)", desc = "suspend", long_desc = "Suspend reconciliation" },
      { key = "<Plug>(kubectl.flux_resume)", desc = "resume", long_desc = "Resume reconciliation" },
      { key = "<Plug>(kubectl.flux_reconcile)", desc = "reconcile", long_desc = "Force reconciliation" },
      { key = "<Plug>(kubectl.describe)", desc = "desc", long_desc = "Describe resource" },
      { key = "<Plug>(kubectl.yaml)", desc = "yaml", long_desc = "View YAML" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "READY",
      "STATUS",
      "AGE",
    },
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.buf_nr, builder.win_nr = buffers.buffer(M.definition.ft, builder.resource)
  M.Draw(cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if not builder then
    return
  end

  local ns = nil
  if state.ns and state.ns ~= "All" then
    ns = state.ns
  end

  local filter = state.getFilter()
  local sort_data = state.sortby[M.definition.resource]

  local fetch_cmds = {}
  for _, res in ipairs(definition.flux_resources) do
    table.insert(fetch_cmds, {
      cmd = "get_fallback_table_async",
      args = {
        gvk = res.gvk,
        namespace = ns,
        filter = filter,
      },
    })
  end

  commands.await_all(fetch_cmds, nil, function(results)
    local all_rows = {}
    local section_starts = {}

    for i, res_def in ipairs(definition.flux_resources) do
      local result = results[i]
      if result and result ~= vim.NIL then
        local decoded = result
        if type(decoded) == "string" then
          local ok, d = pcall(vim.json.decode, decoded, { luanil = { object = true, array = true } })
          if ok then
            decoded = d
          end
        end
        if decoded and decoded.rows and #decoded.rows > 0 then
          local rows = definition.processRow(decoded.rows, res_def.gvk)
          table.insert(section_starts, {
            index = #all_rows + 1,
            label = res_def.label,
            count = #rows,
          })
          vim.list_extend(all_rows, rows)
        end
      end
    end

    builder.processedData = all_rows
    builder.data = all_rows

    vim.schedule(function()
      if sort_data then
        builder.sort()
      end

      local windows = buffers.get_windows_by_name(M.definition.resource)
      for _, win_id in ipairs(windows) do
        builder.prettyPrint(win_id).addDivider(true).addHints(M.definition.hints, true, true)

        -- Add section header extmarks as virtual lines above each group
        if builder.extmarks and #section_starts > 0 then
          local hl_group = "KubectlHeader"
          for _, section in ipairs(section_starts) do
            -- +1 for the column header row in prettyData
            local row_idx = section.index
            table.insert(builder.extmarks, {
              row = row_idx,
              col = 0,
              virt_lines = {
                { { string.format("── %s (%d) ", section.label, section.count), hl_group } },
              },
              virt_lines_above = true,
            })
          end
        end

        builder.displayContent(win_id, cancellationToken)
      end

      local loop = require("kubectl.utils.loop")
      loop.set_running(builder.buf_nr, false)
    end)
  end)
end

function M.Desc(name, ns)
  local gvk = M._get_current_row_gvk()
  if not gvk then
    vim.notify("Cannot determine Flux resource type", vim.log.levels.WARN)
    return
  end
  local describe_session = require("kubectl.views.describe.session")
  describe_session.view(M.definition.resource, name, ns, gvk)
end

function M.Yaml(name, ns)
  local gvk = M._get_current_row_gvk()
  if not gvk then
    return
  end
  local display_ns = ns and (" | " .. ns) or ""
  local title = M.definition.resource .. " | " .. name .. display_ns

  local def = {
    resource = M.definition.resource .. "_yaml",
    ft = "k8s_" .. M.definition.resource .. "_yaml",
    title = title,
    syntax = "yaml",
    cmd = "get_single_async",
    hints = {},
    panes = {
      { title = "YAML" },
    },
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_framed(def, {
    args = {
      gvk = gvk,
      namespace = ns,
      name = name,
      output = "yaml",
    },
    recreate_func = M.Yaml,
    recreate_args = { name, ns },
  })
end

--- Get current selection from buffer
---@return string|nil, string|nil
function M.getCurrentSelection()
  local name_col, ns_col = tables.getColumnIndices(M.definition.resource, M.definition.headers)
  if not name_col then
    return nil, nil
  end
  if ns_col then
    return tables.getCurrentSelection(name_col, ns_col)
  end
  return tables.getCurrentSelection(name_col), nil
end

--- Get the GVK for the resource on the current cursor line
---@return table|nil
function M._get_current_row_gvk()
  local builder = manager.get(M.definition.resource)
  if not builder or not builder.processedData then
    return nil
  end
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  -- Subtract header row offset
  local data_index = cursor_line - 1
  local row = builder.processedData[data_index]
  if row and row._gvk then
    return row._gvk
  end
  return nil
end

return M
