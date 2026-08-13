local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.resources.argocd.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = {
    resource = "argocd",
    display_name = "ArgoCD",
    ft = "k8s_argocd",
    hints = {
      { key = "<Plug>(kubectl.describe)", desc = "desc", long_desc = "Describe resource" },
      { key = "<Plug>(kubectl.yaml)", desc = "yaml", long_desc = "View YAML" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "SYNC",
      "HEALTH",
      "AUTOSYNC",
      "OWNER",
      "PROJECT",
      "AGE",
    },
  },
}

--- Sort one section's rows using the builder's shared comparator, so sorting
--- behaves identically to every other view without flattening the grouping.
---@param builder table
---@param rows table[]
local function sort_section(builder, rows)
  local previous = builder.processedData
  builder.processedData = rows
  builder.sort()
  builder.processedData = previous
end

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
  for _, res in ipairs(definition.argocd_resources) do
    table.insert(fetch_cmds, {
      cmd = "get_fallback_table_async",
      args = {
        gvk = res.gvk,
        namespace = ns,
        filter = filter,
      },
    })
  end

  -- The fallback table only exposes each CRD's additionalPrinterColumns, which
  -- cover neither syncPolicy.automated nor ownerReferences, so pull the raw
  -- objects too. Indices are tracked because await_all keys results by
  -- fetch position.
  local raw_index_of = {}
  for i, res in ipairs(definition.argocd_resources) do
    if res.fetch_raw then
      table.insert(fetch_cmds, {
        cmd = "get_all_async",
        args = {
          gvk = res.gvk,
          namespace = ns,
        },
      })
      raw_index_of[i] = #fetch_cmds
    end
  end

  commands.await_all(fetch_cmds, nil, function(results)
    builder.data = results
    builder.decodeJson()

    local sections = {}

    for i, res_def in ipairs(definition.argocd_resources) do
      local decoded = builder.data[i]
      if decoded and decoded ~= vim.NIL and decoded.rows and #decoded.rows > 0 then
        local extras = {}
        local raw_index = raw_index_of[i]
        if raw_index then
          local raw = builder.data[raw_index]
          if raw and raw ~= vim.NIL then
            extras = definition.buildRowExtras(raw, res_def.autosync_path)
          end
        end

        table.insert(sections, {
          label = res_def.label,
          rows = definition.processRow(decoded.rows, res_def.gvk, extras),
        })
      end
    end

    vim.schedule(function()
      -- Sort within each section rather than across the flat list, otherwise
      -- kinds interleave and the section headers no longer match their rows.
      if sort_data then
        for _, section in ipairs(sections) do
          sort_section(builder, section.rows)
        end
      end

      local all_rows = {}
      local section_starts = {}
      for _, section in ipairs(sections) do
        table.insert(section_starts, {
          index = #all_rows + 1,
          label = section.label,
          count = #section.rows,
        })
        vim.list_extend(all_rows, section.rows)
      end

      builder.processedData = all_rows
      builder.data = all_rows

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
    vim.notify("Cannot determine ArgoCD resource type", vim.log.levels.WARN)
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
    ft = "k8s_yaml",
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
