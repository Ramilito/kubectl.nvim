local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.lineage.definition")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")

local M = {
  selection = {},
  builder = nil,
  loaded = false,
  is_loading = false,
  is_building_graph = false,
  graph = nil,
  processed = 0,
  total = 0,
}

M.definition = {
  resource = "Lineage",
  ft = "k8s_lineage",
  title = "Lineage",
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "go to" },
    { key = "<Plug>(kubectl.refresh)", desc = "refresh cache" },
    { key = "<Plug>(kubectl.export_dot)", desc = "export DOT" },
    { key = "<Plug>(kubectl.export_mermaid)", desc = "export Mermaid" },
  },
  panes = {
    { title = "Lineage" },
  },
}

vim.api.nvim_create_autocmd("User", {
  pattern = "K8sLineageDataLoaded",
  callback = function()
    -- Cache is loaded, now build the graph asynchronously
    M.build_graph()
  end,
})

--- Generate content for the lineage view
--- @return { content: table, marks: table, header_data: table, header_marks: table }
function M.generate_content()
  local content = {}
  local marks = {}
  local header_data = {}
  local header_marks = {}

  if cache.loading or M.is_loading then
    table.insert(content, "Associated Resources:")
    table.insert(content, "")
    table.insert(content, M.processed .. "/" .. M.total)
    table.insert(content, "Cache still loading...")
  elseif M.is_building_graph then
    table.insert(content, "Building lineage graph...")
  elseif not M.graph then
    table.insert(content, "No graph available. Press r to refresh.")
  else
    -- Convert plural resource name to singular using cached API resources
    local kind = M.selection.kind
    local ns, name = M.selection.ns, M.selection.name

    -- Look up the actual kind from cached API resources (authoritative source)
    local resource_info = cache.cached_api_resources.values[string.lower(kind)]
      or cache.cached_api_resources.shortNames[string.lower(kind)]

    if resource_info and resource_info.gvk and resource_info.gvk.k then
      kind = resource_info.gvk.k
    end
    -- No fallback - use GVK lookup exclusively. If not found, use as-is.

    kind = string.lower(kind)

    -- Build the key with lowercase to match Rust's TreeNode::get_resource_key
    local selected_key = kind
    if ns then
      selected_key = selected_key .. "/" .. string.lower(ns)
    end
    selected_key = selected_key .. "/" .. string.lower(name)

    content, marks = definition.build_display_lines(M.graph, selected_key)

    -- Add cache timestamp to header
    if cache.timestamp and not cache.loading then
      local time = os.date("%H:%M:%S", cache.timestamp)
      local line = "Associated Resources - Cache refreshed at: " .. time
      table.insert(header_data, line)
      table.insert(header_marks, {
        row = 0,
        start_col = 0,
        end_col = #line,
        hl_group = hl.symbols.gray,
      })
    else
      table.insert(header_data, "Associated Resources")
    end
  end

  return {
    content = content,
    marks = marks,
    header_data = header_data,
    header_marks = header_marks,
  }
end

--- Build the lineage graph asynchronously
function M.build_graph()
  if M.is_building_graph then
    -- Already building, just update display to show status
    M.Draw()
    return
  end

  M.is_building_graph = true
  M.graph = nil
  M.Draw() -- Show "Building..." message

  local data = definition.collect_all_resources(cache.cached_api_resources.values)
  definition.build_graph_async(data, function(graph)
    M.graph = graph
    M.is_building_graph = false
    -- Only draw if buffer still exists
    if M.builder and vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
      M.Draw()
    end
  end)
end

function M.View(name, ns, kind)
  if cache.loading then
    vim.notify("cache is not ready")
    return
  end

  M.total = 0
  for _, _ in pairs(cache.cached_api_resources.values) do
    M.total = M.total + 1
  end

  if M.total == 0 then
    vim.notify("cache is not ready")
    return
  end

  -- Check if this is the same selection and we already have/are building a graph
  local same_selection = M.selection.name == name and M.selection.ns == ns and M.selection.kind == kind
  local has_existing_state = same_selection and (M.graph or M.is_building_graph)

  -- Only reset if it's a different selection
  if not same_selection then
    M.graph = nil
    M.is_building_graph = false
  end

  M.selection.name = name
  M.selection.ns = ns
  M.selection.kind = kind

  if not M.loaded and not M.is_loading then
    M.is_loading = true
    M.load_cache()
  end

  M.builder = manager.get_or_create(M.definition.resource)
  M.builder.view_framed(M.definition)

  -- If we already have a graph or are building one, just draw
  if has_existing_state then
    M.Draw()
  elseif M.loaded and not M.is_loading then
    -- Cache is loaded, start building graph
    M.build_graph()
  else
    M.Draw() -- Show loading message
  end
end

function M.Draw()
  if not M.builder or not vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
    return
  end

  local result = M.generate_content()

  buffers.set_content(M.builder.buf_nr, {
    content = result.content,
    marks = result.marks,
    header = { data = result.header_data, marks = result.header_marks },
  })

  M.set_folding(M.builder.win_nr, M.builder.buf_nr)

  if M.builder.frame then
    M.builder.fitToContent(1)
  end

  collectgarbage("collect")
end

function M.load_cache(callback)
  local cached_api_resources = cache.cached_api_resources
  local all_gvk = {}
  M.processed = 0
  for _, resource in pairs(cached_api_resources.values) do
    if resource.gvk then
      table.insert(all_gvk, { cmd = "get_all_async", args = { gvk = resource.gvk } })
    end
  end

  collectgarbage("collect")

  -- Memory usage before creating the table
  local mem_before = collectgarbage("count")

  commands.await_all(all_gvk, function()
    M.processed = M.processed + 1
    vim.schedule(function()
      if M.builder and M.builder.buf_nr and vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
        M.Draw()
      end
    end)
  end, function(data)
    M.builder.data = data
    M.builder.splitData()
    M.builder.decodeJson()
    M.builder.processedData = {}

    for _, values in pairs(M.builder.data) do
      definition.processRow(values, cached_api_resources)
    end

    -- Memory usage after creating the table
    collectgarbage("collect")
    local mem_after = collectgarbage("count")
    local mem_diff_mb = (mem_after - mem_before) / 1024

    print("Memory used by the table (in MB):", mem_diff_mb)
    print("finished loading cache")

    M.is_loading = false
    M.loaded = true
    if callback then
      callback()
    end
    vim.schedule(function()
      vim.cmd("doautocmd User K8sLineageDataLoaded")
    end)
  end)
end

function M.set_folding(win_nr, buf_nr)
  if not vim.api.nvim_win_is_valid(win_nr) then
    return
  end
  -- Set indent options for proper fold calculation
  vim.api.nvim_set_option_value("shiftwidth", 4, { scope = "local", buf = buf_nr })
  vim.api.nvim_set_option_value("tabstop", 4, { scope = "local", buf = buf_nr })
  vim.api.nvim_set_option_value("expandtab", true, { scope = "local", buf = buf_nr })

  -- Use Neovim's native indent-based folding
  vim.api.nvim_set_option_value("foldmethod", "indent", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldenable", true, { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldtext", "", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldcolumn", "auto:4", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldlevel", 99, { scope = "local", win = win_nr })

  -- Better fold indicators, hide tildes and fold separator lines
  vim.api.nvim_set_option_value(
    "fillchars",
    "fold: ,foldopen:▼,foldclose:▶,foldsep: ,eob: ",
    { scope = "local", win = win_nr }
  )
end
--- Get current selection for view
function M.getCurrentSelection()
  local line = vim.api.nvim_get_current_line()
  local selection = vim.split(line, ":")
  local columns = vim.split(selection[2], "/")

  local kind = string.lower(vim.trim(selection[1]))
  local ns = vim.trim(columns[1])
  local name = vim.trim(columns[2])

  return kind, ns, name
end

return M
