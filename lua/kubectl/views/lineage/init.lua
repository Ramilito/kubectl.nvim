local cache = require("kubectl.cache")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.lineage.definition")
local graph_mod = require("kubectl.views.lineage.graph")
local manager = require("kubectl.resource_manager")
local renderer = require("kubectl.views.lineage.renderer")
local state = require("kubectl.state")

local M = {
  builder = nil,
}

-- ---------------------------------------------------------------------------
-- View state (grouped, accessed via public API functions)
-- ---------------------------------------------------------------------------

local view_state = {
  -- State machine: "idle" | "loading" | "building" | "ready" | "error"
  phase = "idle",
  selection = {},
  graph = nil,
  orphan_filter_enabled = false,
  processed = 0,
  total = 0,
  line_nodes = {},
  progress_timer = nil,
}

-- ---------------------------------------------------------------------------
-- Progress timer
-- ---------------------------------------------------------------------------

local function stop_progress_timer()
  if view_state.progress_timer then
    ---@diagnostic disable-next-line: undefined-field
    view_state.progress_timer:stop()
    ---@diagnostic disable-next-line: undefined-field
    view_state.progress_timer:close()
    view_state.progress_timer = nil
  end
end

local function start_progress_timer()
  stop_progress_timer()
  view_state.progress_timer = vim.uv.new_timer()
  ---@diagnostic disable-next-line: undefined-field
  view_state.progress_timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if view_state.phase == "loading" and M.builder and vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
        M.Draw()
      else
        stop_progress_timer()
      end
    end)
  )
end

-- ---------------------------------------------------------------------------
-- Selected key computation
-- ---------------------------------------------------------------------------

local function compute_selected_key(selection)
  local kind = selection.kind
  local ns, name = selection.ns, selection.name

  local resource_info = cache.cached_api_resources.values[string.lower(kind)]
    or cache.cached_api_resources.shortNames[string.lower(kind)]

  if resource_info and resource_info.gvk and resource_info.gvk.k then
    kind = resource_info.gvk.k
  end

  kind = string.lower(kind)
  local key = kind
  if ns then
    key = key .. "/" .. string.lower(ns)
  end
  key = key .. "/" .. string.lower(name)
  return key
end

-- ---------------------------------------------------------------------------
-- Draw pipeline
-- ---------------------------------------------------------------------------

function M.Draw()
  if not M.builder or not vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
    return
  end

  local ctx = renderer.RenderContext.new()

  if view_state.phase == "loading" then
    renderer.render_status(ctx, "loading", { view_state.processed, view_state.total })
  elseif view_state.phase == "building" then
    renderer.render_status(ctx, "building")
  elseif view_state.phase == "ready" and view_state.graph then
    renderer.render_header(ctx, cache.timestamp, cache.loading, view_state.orphan_filter_enabled)

    if view_state.orphan_filter_enabled then
      renderer.render_orphans(ctx, view_state.graph)
    else
      local selected_key = compute_selected_key(view_state.selection)
      renderer.render_tree(ctx, view_state.graph, selected_key)
    end
  elseif view_state.phase == "error" then
    renderer.render_error(ctx)
  else
    renderer.render_status(ctx, "empty")
  end

  local result = ctx:get()
  view_state.line_nodes = result.line_nodes or {}

  M.builder.data = result.lines
  M.builder.extmarks = result.marks
  M.builder.header = { data = result.header_data, marks = result.header_marks }
  M.builder.displayContentRaw()

  M.set_folding(M.builder.win_nr, M.builder.buf_nr)

  if M.builder.frame then
    M.builder.fitToContent(1)
  end

  collectgarbage("collect")
end

-- ---------------------------------------------------------------------------
-- Graph building
-- ---------------------------------------------------------------------------

local function build_graph()
  if view_state.phase == "building" then
    M.Draw()
    return
  end

  view_state.phase = "building"
  view_state.graph = nil
  M.Draw()

  local data = graph_mod.collect_all_resources(cache.cached_api_resources.values)
  graph_mod.build_graph_async(data, function(graph)
    view_state.graph = graph
    view_state.phase = graph and "ready" or "error"
    if M.builder and vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
      M.Draw()
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Cache loading
-- ---------------------------------------------------------------------------

function M.load_cache(callback)
  local cached_api_resources = cache.cached_api_resources
  local all_gvk = {}
  view_state.processed = 0

  for _, resource in pairs(cached_api_resources.values) do
    if resource.gvk then
      table.insert(all_gvk, { cmd = "get_all_async", args = { gvk = resource.gvk } })
    end
  end

  collectgarbage("collect")
  start_progress_timer()

  local mem_before = collectgarbage("count")

  commands.await_all(all_gvk, function()
    view_state.processed = view_state.processed + 1
  end, function(data)
    M.builder.data = data
    M.builder.splitData()
    M.builder.decodeJson()
    M.builder.processedData = {}

    for _, values in pairs(M.builder.data) do
      graph_mod.processRow(values, cached_api_resources)
    end

    collectgarbage("collect")
    local mem_after = collectgarbage("count")
    local mem_diff_mb = (mem_after - mem_before) / 1024

    print("Memory used by the table (in MB):", mem_diff_mb)
    print("finished loading cache")

    if callback then
      callback()
    end

    vim.schedule(function()
      stop_progress_timer()
      view_state.phase = "idle"
      vim.cmd("doautocmd User K8sLineageDataLoaded")
      build_graph()
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.View(name, ns, kind)
  if cache.loading then
    vim.notify("cache is not ready")
    return
  end

  if not next(cache.cached_api_resources.values) then
    vim.notify("cache is not ready")
    return
  end

  local same_selection = view_state.selection.name == name
    and view_state.selection.ns == ns
    and view_state.selection.kind == kind
  local has_existing_state = same_selection and (view_state.graph or view_state.phase == "building")

  if not same_selection then
    view_state.graph = nil
    view_state.phase = "idle"
  end

  view_state.selection.name = name
  view_state.selection.ns = ns
  view_state.selection.kind = kind

  M.builder = manager.get_or_create(definition.resource)
  M.builder.view_framed({
    resource = definition.resource,
    ft = definition.ft,
    title = definition.title,
    hints = definition.hints,
    panes = definition.panes,
  }, {
    recreate_func = M.View,
    recreate_args = { name, ns, kind },
  })

  state.addToHistory(definition.resource)

  -- Clean up timer when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = M.builder.buf_nr,
    once = true,
    callback = function()
      stop_progress_timer()
      view_state.phase = "idle"
    end,
  })

  if view_state.phase == "idle" and not view_state.graph then
    -- Count total resources for progress display
    view_state.total = 0
    for _, resource in pairs(cache.cached_api_resources.values) do
      if resource.gvk then
        view_state.total = view_state.total + 1
      end
    end

    view_state.phase = "loading"
    M.load_cache()
    M.Draw()
  elseif has_existing_state then
    M.Draw()
  elseif view_state.phase == "ready" or (view_state.phase == "idle" and view_state.graph) then
    build_graph()
  end
end

function M.refresh()
  if view_state.phase == "loading" or view_state.phase == "building" then
    vim.notify("Already loading, please wait...", vim.log.levels.INFO)
    return
  end

  view_state.phase = "idle"
  view_state.graph = nil
  view_state.processed = 0

  view_state.total = 0
  for _, resource in pairs(cache.cached_api_resources.values) do
    if resource.gvk then
      view_state.total = view_state.total + 1
    end
  end

  view_state.phase = "loading"
  M.Draw()
  M.load_cache()
end

--- Get current selection for view
--- @return string|nil kind
--- @return string|nil ns
--- @return string|nil name
function M.getCurrentSelection()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local node = view_state.line_nodes[line_nr]

  if not node then
    return nil, nil, nil
  end

  local ns = node.ns
  if ns == nil or ns == vim.NIL then
    ns = "cluster"
  end

  return node.kind, ns, node.name
end

-- ---------------------------------------------------------------------------
-- Accessor functions (for mappings.lua to reduce coupling)
-- ---------------------------------------------------------------------------

--- Toggle orphan filter and redraw.
function M.toggle_orphan_filter()
  view_state.orphan_filter_enabled = not view_state.orphan_filter_enabled
  local status = view_state.orphan_filter_enabled and "enabled" or "disabled"
  vim.notify("Orphan filter " .. status, vim.log.levels.INFO)
  M.Draw()
end

--- Get the current graph, or nil if not ready.
--- @return table|nil
function M.get_graph()
  return view_state.graph
end

--- Get the line node at the given line number.
--- @param line_nr number 1-indexed line number
--- @return table|nil
function M.get_line_node(line_nr)
  return view_state.line_nodes[line_nr]
end

function M.set_folding(win_nr, buf_nr)
  if not vim.api.nvim_win_is_valid(win_nr) then
    return
  end
  vim.api.nvim_set_option_value("shiftwidth", 4, { scope = "local", buf = buf_nr })
  vim.api.nvim_set_option_value("tabstop", 4, { scope = "local", buf = buf_nr })
  vim.api.nvim_set_option_value("expandtab", true, { scope = "local", buf = buf_nr })
  vim.api.nvim_set_option_value("foldmethod", "indent", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldenable", true, { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldtext", "", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldcolumn", "auto:4", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldlevel", 99, { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value(
    "fillchars",
    "fold: ,foldopen:\226\150\188,foldclose:\226\150\182,foldsep: ,eob: ",
    { scope = "local", win = win_nr }
  )
end

return M
