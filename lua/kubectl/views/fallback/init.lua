local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.fallback.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}
M.resource = ""

local function get_args()
  local ns_filter = state.getNamespace()
  local args = { "get", M.resource, "-o=json" }
  if ns_filter == "All" then
    table.insert(args, "-A")
  else
    table.insert(args, "--namespace")
    table.insert(args, ns_filter)
  end
  return args
end

function M.View(cancellationToken, resource)
  if resource then
    M.resource = resource
  end

  ResourceBuilder:new(M.resource)
    :display("k8s_fallback", "fallback", cancellationToken)
    :setCmd(get_args())
    :fetchAsync(function(self)
      self:decodeJson()
      vim.schedule(function()
        self
          :process(definition.processRow)
          :sort()
          :prettyPrint(definition.getHeaders)
          :addHints({
            { key = "<gd>", desc = "describe" },
          }, true, true, true)
          :setContent(cancellationToken)
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_fallback_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", M.resource .. "/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_fallback_desc", name, "yaml")
    :setCmd({ "describe", M.resource, name, "-n", ns })
    :fetch()
    :splitData()
    :setContentRaw()
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
