local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")

local M = {}

function M.Hints(hint)
  local hints = {}
  local line = hl.symbols.success
    .. "Buffer mappings: \n"
    .. hl.symbols.clear
    .. hint
    .. "\n"
    .. hl.symbols.success
    .. "Global mappings: \n"
    .. hl.symbols.clear
    .. tables.generateHintLine("<C-f>", "Filter on a phrase\n")
    .. tables.generateHintLine("<C-n>", "Change namespace \n")
    .. tables.generateHintLine("<1>", "Deployments \n")
    .. tables.generateHintLine("<2>", "Pods \n")
    .. tables.generateHintLine("<3>", "Configmaps \n")
    .. tables.generateHintLine("<4>", "Secrets \n")
    .. tables.generateHintLine("<5>", "Services \n")

  table.insert(hints, line)
  actions.floating_buffer(vim.split(table.concat(hints, ""), "\n"), "k8s_hints", { title = "Hints" })
end

function M.UserCmd(args)
  local builder = ResourceBuilder:new("k8s_usercmd", args):fetch():splitData()
  builder.prettyData = builder.data
  builder:display("k8s_usercmd", "UserCmd")
end

return M
