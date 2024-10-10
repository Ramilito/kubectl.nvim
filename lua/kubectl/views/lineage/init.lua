local ResourceBuilder = require("kubectl.resourcebuilder")
local cache = require("kubectl.utils.cache")
local definition = require("kubectl.views.lineage.definition")
local logger = require("kubectl.utils.logging")
local view = require("kubectl.views")

local M = {}

function M.View(name, ns, kind)
  local builder = ResourceBuilder:new(definition.resource)
  builder:displayFloatFit(definition.ft, definition.resource, definition.syntax)

  local hints = {
    { key = "<Plug>(kubectl.select)", desc = "go to" },
  }

  builder.data = { "Associated Resources: " }
  if cache.loading then
    table.insert(builder.data, "")
    table.insert(builder.data, "Cache still loading...")
  else
    local data = definition.collect_all_resources(view.cached_api_resources.values)
    local graph = definition.build_graph(data)

    -- TODO: Our views are in plural form, we remove the last s for that...not really that robust
    if kind:sub(-1) == "s" then
      kind = kind:sub(1, -2)
    end
    local selected_key = kind
    if ns then
      selected_key = selected_key .. "/" .. ns
    end
    selected_key = selected_key .. "/" .. name

    builder.data, builder.extmarks = definition.build_display_lines(graph, selected_key)
  end

  builder:splitData()
  builder:addHints(hints, false, false, false)
  builder:setContentRaw()

  -- set fold options
  vim.api.nvim_set_option_value("foldmethod", "indent", { scope = "local", win = builder.win_nr })
  vim.api.nvim_set_option_value("foldenable", true, { win = builder.win_nr })
  vim.api.nvim_set_option_value("foldtext", "", { win = builder.win_nr })
  vim.api.nvim_set_option_value("foldcolumn", "1", { win = builder.win_nr })

  local fcs = { foldclose = "", foldopen = "" }
  local function get_fold(lnum)
    if vim.fn.foldlevel(lnum) <= vim.fn.foldlevel(lnum - 1) then
      return " "
    end
    return vim.fn.foldclosed(lnum) == -1 and fcs.foldopen or fcs.foldclose
  end
  _G.kubectl_get_statuscol = function()
    return "%s%l " .. get_fold(vim.v.lnum) .. " "
  end
  vim.api.nvim_set_option_value(
    "statuscolumn",
    "%!v:lua.kubectl_get_statuscol()",
    { scope = "local", win = builder.win_nr }
  )
end

return M
