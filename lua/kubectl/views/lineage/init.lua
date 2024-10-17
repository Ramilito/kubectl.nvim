local ResourceBuilder = require("kubectl.resourcebuilder")
local cache = require("kubectl.cache")
local definition = require("kubectl.views.lineage.definition")
local hl = require("kubectl.actions.highlight")
local mappings = require("kubectl.mappings")
local view = require("kubectl.views")

local M = {
  selection = {},
  builder = nil,
}

function M.View(name, ns, kind)
  M.builder = nil
  M.selection.name = name
  M.selection.ns = ns
  M.selection.kind = kind

  M.builder = ResourceBuilder:new(definition.resource)
  M.builder:displayFloatFit(definition.ft, definition.resource, definition.syntax)
  M.Draw()
end

function M.Draw()
  if vim.api.nvim_get_current_buf() ~= M.builder.buf_nr then
    return
  end

  local kind, ns, name = M.selection.kind, M.selection.ns, M.selection.name
  M.builder.data = { "Associated Resources: " }
  if cache.loading then
    table.insert(M.builder.data, "")
    table.insert(M.builder.data, "Cache still loading...")
  else
    local data = definition.collect_all_resources(cache.cached_api_resources.values)
    local graph = definition.build_graph(data)

    -- TODO: Our views are in plural form, we remove the last s for that...not really that robust
    if
      kind:sub(-1) == "s"
      and kind ~= "ingresses"
      and kind ~= "storageclasses"
      and kind ~= "sa"
      and kind ~= "ingressclasses"
    then
      kind = kind:sub(1, -2)
    elseif kind == "storageclasses" then
      kind = "storageclass"
    elseif kind == "ingresses" then
      kind = "ingress"
    elseif kind == "ingressclasses" then
      kind = "ingressclass"
    elseif kind == "sa" then
      kind = "serviceaccount"
    end
    local selected_key = kind
    if ns then
      selected_key = selected_key .. "/" .. ns
    end
    selected_key = selected_key .. "/" .. name

    M.builder.data, M.builder.extmarks = definition.build_display_lines(graph, selected_key)
  end

  M.builder:splitData()

  M.set_keymaps(M.builder.buf_nr)

  vim.schedule(function()
    mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
    mappings.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
    M.builder:addHints({
      { key = "<Plug>(kubectl.select)", desc = "go to" },
      { key = "<Plug>(kubectl.refresh)", desc = "refresh cache" },
    }, false, false, false)
    if cache.timestamp and not cache.loading then
      local time = os.date("%H:%M:%S", cache.timestamp)
      local line = "Cache refreshed at: " .. time
      table.insert(M.builder.header.marks, {
        row = #M.builder.header.data or 0,
        start_col = 0,
        end_col = #line,
        hl_group = hl.symbols.gray,
      })
      table.insert(M.builder.header.data, line)
    end

    M.builder:setContentRaw()
    M.set_folding(M.builder.win_nr)
    collectgarbage("collect")
  end)
end

function M.set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local kind, name, ns = M.getCurrentSelection()
      if name and ns then
        vim.api.nvim_set_option_value("modified", false, { buf = 0 })
        vim.cmd.close()

        view.view_or_fallback(kind)
      else
        vim.api.nvim_err_writeln("Failed to select resource.")
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.refresh)", "", {
    noremap = true,
    silent = true,
    desc = "Refresh",
    callback = function()
      cache.LoadFallbackData(true, function()
        vim.schedule(function()
          M.Draw()
        end)
      end)
    end,
  })
end

function M.set_folding(win_nr)
  -- Set fold options using nvim_set_option_value
  vim.api.nvim_set_option_value("foldmethod", "expr", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldexpr", "v:lua.kubectl_fold_expr(v:lnum)", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldenable", true, { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldtext", "", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("foldcolumn", "1", { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("shiftwidth", 4, { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("tabstop", 4, { scope = "local", win = win_nr })
  vim.api.nvim_set_option_value("expandtab", false, { scope = "local", win = win_nr })

  -- Corrected fold expression function
  _G.kubectl_fold_expr = function(lnum)
    local shiftwidth = vim.api.nvim_get_option_value("shiftwidth", { scope = "local", win = win_nr })
    shiftwidth = shiftwidth > 0 and shiftwidth or 1

    local indent = vim.fn.indent(lnum)
    local level = math.floor(indent / shiftwidth)

    return level
  end

  local fcs = { foldclose = "", foldopen = "" }

  -- Updated fold start detection function
  local function kubectl_is_fold_start(lnum)
    if lnum == 1 then
      return false
    end

    local shiftwidth = vim.api.nvim_get_option_value("shiftwidth", { scope = "local", win = win_nr })
    shiftwidth = shiftwidth > 0 and shiftwidth or 1

    local current_indent = vim.fn.indent(lnum)
    local prev_indent = vim.fn.indent(lnum - 1)

    local current_level = math.floor(current_indent / shiftwidth)
    local prev_level = math.floor(prev_indent / shiftwidth)

    return current_level > prev_level
  end

  -- Function to get the appropriate fold icon
  local function get_fold(lnum)
    if kubectl_is_fold_start(lnum) then
      local fold_closed = vim.fn.foldclosed(lnum)
      if fold_closed == -1 then
        -- Fold is open
        return fcs.foldopen
      else
        -- Fold is closed
        return fcs.foldclose
      end
    else
      -- Not the start of a fold, no icon
      return "  "
    end
  end

  -- Define the status column function
  _G.kubectl_get_statuscol = function()
    return string.format("%s%3d %s", " ", vim.v.lnum, get_fold(vim.v.lnum))
  end

  vim.api.nvim_set_option_value("statuscolumn", "%!v:lua.kubectl_get_statuscol()", { scope = "local", win = win_nr })
end
--- Get current seletion for view
function M.getCurrentSelection()
  local line = vim.api.nvim_get_current_line()
  local selection = vim.split(line, ":")
  local columns = vim.split(selection[2], "/")

  local kind = vim.trim(selection[1])
  local name = vim.trim(columns[1])
  local ns = vim.trim(columns[2])
  if kind:sub(-1) ~= "s" then
    kind = kind .. "s"
  end
  return kind, name, ns
end

return M
