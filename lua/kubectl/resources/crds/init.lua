local BaseResource = require("kubectl.resources.base_resource")
local buffers = require("kubectl.actions.buffers")
local describe_session = require("kubectl.views.describe.session")
local manager = require("kubectl.resource_manager")

local resource = "crds"

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "apiextensions.k8s.io", v = "v1", k = "CustomResourceDefinition" },
  plural = "customresourcedefinitions",
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "resource", long_desc = "Open resource view" },
  },
  headers = {
    "NAME",
    "GROUP",
    "KIND",
    "VERSIONS",
    "SCOPE",
    "AGE",
  },
})

M.selection = {}

-- Override Desc to use plural for the gvk.k
function M.Desc(name, _, _)
  local title = M.definition.resource .. " | " .. name

  -- Get or reuse existing window
  local builder = manager.get(M.definition.resource .. "_desc")
  local existing_win = builder and builder.win_nr or nil

  -- Create floating buffer
  local buf, win = buffers.floating_buffer("k8s_desc", title, "yaml", existing_win)

  -- Store in manager for window reuse
  local new_builder = manager.get_or_create(M.definition.resource .. "_desc")
  new_builder.buf_nr = buf
  new_builder.win_nr = win

  -- Start the describe session (handles polling internally)
  -- Use plural for the gvk.k as CRDs need it
  local gvk = { k = M.definition.plural, g = M.definition.gvk.g, v = M.definition.gvk.v }
  describe_session.start(name, nil, gvk, buf, win)
end

return M
