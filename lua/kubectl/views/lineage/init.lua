local cache = require("kubectl.cache")
local definition = require("kubectl.views.lineage.definition")
local graph_mod = require("kubectl.views.lineage.graph")
local manager = require("kubectl.resource_manager")
local renderer = require("kubectl.views.lineage.renderer")
local state = require("kubectl.state")

local M = { builder = nil }

local phase = "idle"
local selection = {}
local graph = nil
local orphan_filter = false
local processed, total = 0, 0
local line_nodes = {}
local progress_timer = nil

local function stop_progress_timer()
  if progress_timer then
    progress_timer:stop()
    progress_timer:close()
    progress_timer = nil
  end
end

local function start_progress_timer()
  stop_progress_timer()
  progress_timer = vim.uv.new_timer()
  progress_timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if phase == "loading" and M.builder and vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
        M.Draw()
      else
        stop_progress_timer()
      end
    end)
  )
end

function M.get_selected_key()
  local kind = selection.kind
  local ns, name = selection.ns, selection.name

  local info = cache.cached_api_resources.values[string.lower(kind)]
    or cache.cached_api_resources.shortNames[string.lower(kind)]
  if info and info.gvk and info.gvk.k then
    kind = info.gvk.k
  end

  kind = string.lower(kind)
  local key = kind
  if ns then
    key = key .. "/" .. string.lower(ns)
  end
  return key .. "/" .. string.lower(name)
end

local function on_graph_result(result)
  graph = result
  phase = result and "ready" or "error"
  if M.builder and vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
    M.Draw()
  end
end

function M.Draw()
  if not M.builder or not vim.api.nvim_buf_is_valid(M.builder.buf_nr) then
    return
  end

  local ctx = renderer.RenderContext.new()

  if phase == "loading" then
    renderer.render_status(ctx, "loading", { processed, total })
  elseif phase == "building" then
    renderer.render_status(ctx, "building")
  elseif phase == "ready" and graph then
    renderer.render_header(ctx, cache.timestamp, cache.loading, orphan_filter)
    if orphan_filter then
      renderer.render_orphans(ctx, graph)
    else
      renderer.render_tree(ctx, graph, M.get_selected_key())
    end
  elseif phase == "error" then
    renderer.render_error(ctx)
  else
    renderer.render_status(ctx, "empty")
  end

  local result = ctx:get()
  line_nodes = result.line_nodes or {}

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

local function begin_loading(force_refresh)
  processed, total = 0, graph_mod.count_gvk_resources()
  phase = "loading"
  M.Draw()
  start_progress_timer()

  graph_mod.load_and_build(function()
    processed = processed + 1
  end, function()
    stop_progress_timer()
    phase = "building"
    graph = nil
    M.Draw()
  end, on_graph_result, force_refresh)
end

local function rebuild_graph()
  if phase == "building" then
    return M.Draw()
  end
  phase = "building"
  graph = nil
  M.Draw()

  local data = graph_mod.collect_all_resources(cache.cached_api_resources.values)
  graph_mod.build_graph_async(data, on_graph_result)
end

function M.View(name, ns, kind)
  if cache.loading or not next(cache.cached_api_resources.values) then
    vim.notify("cache is not ready")
    return
  end

  local same = selection.name == name and selection.ns == ns and selection.kind == kind
  local reusable = same and (graph or phase == "building")

  if not same then
    graph = nil
    phase = "idle"
  end

  selection.name, selection.ns, selection.kind = name, ns, kind

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

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = M.builder.buf_nr,
    once = true,
    callback = function()
      stop_progress_timer()
      phase = "idle"
    end,
  })

  if phase == "idle" and not graph then
    begin_loading()
  elseif reusable then
    M.Draw()
  elseif phase == "ready" or (phase == "idle" and graph) then
    rebuild_graph()
  end
end

function M.refresh()
  if phase == "loading" or phase == "building" then
    vim.notify("Already loading, please wait...", vim.log.levels.INFO)
    return
  end
  graph = nil
  begin_loading(true)
end

function M.getCurrentSelection()
  local header_count = M.builder and M.builder.header and M.builder.header.data and #M.builder.header.data or 0
  local line_nr = vim.api.nvim_win_get_cursor(0)[1] - header_count
  local node = line_nodes[line_nr]
  if not node then
    return nil, nil, nil
  end
  local ns = node.ns
  if ns == nil or ns == vim.NIL then
    ns = "cluster"
  end
  return node.kind, ns, node.name
end

function M.toggle_orphan_filter()
  orphan_filter = not orphan_filter
  M.Draw()
end

function M.get_graph()
  return graph
end

function M.get_line_node(line_nr)
  local header_count = M.builder and M.builder.header and M.builder.header.data and #M.builder.header.data or 0
  return line_nodes[line_nr - header_count]
end

local folding_buf_opts = { shiftwidth = 4, tabstop = 4, expandtab = true }
local folding_win_opts = {
  foldmethod = "indent",
  foldenable = true,
  foldtext = "",
  foldcolumn = "1",
  foldlevel = 99,
  fillchars = "fold: ,foldopen:\226\150\188,foldclose:\226\150\182,foldsep: ,eob: ",
}

function M.set_folding(win_nr, buf_nr)
  if not vim.api.nvim_win_is_valid(win_nr) then
    return
  end
  for opt, val in pairs(folding_buf_opts) do
    vim.api.nvim_set_option_value(opt, val, { scope = "local", buf = buf_nr })
  end
  for opt, val in pairs(folding_win_opts) do
    vim.api.nvim_set_option_value(opt, val, { scope = "local", win = win_nr })
  end
end

return M
