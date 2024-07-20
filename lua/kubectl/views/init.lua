local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")

local M = {}

--- Generate hints and display them in a floating buffer
---@alias Hint { key: string, desc: string }
---@param headers Hint[]
function M.Hints(headers)
  local marks = {}
  local hints = {}
  local globals = {
    { key = "<C-e>", desc = "Edit resource" },
    { key = "<C-f>", desc = "Filter on a phrase" },
    { key = "<C-n>", desc = "Change namespace" },
    { key = "<C-d>", desc = "Delete resource" },
    { key = "<bs> ", desc = "Go up a level" },
    { key = "<R>  ", desc = "Refresh view" },
    { key = "<1>  ", desc = "Deployments" },
    { key = "<2>  ", desc = "Pods " },
    { key = "<3>  ", desc = "Configmaps " },
    { key = "<4>  ", desc = "Secrets " },
    { key = "<5>  ", desc = "Services" },
  }

  local title = "Buffer mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  local start_row = #hints
  for index, header in ipairs(headers) do
    local line = header.key .. " " .. header.desc
    table.insert(hints, line .. "\n")
    tables.add_mark(marks, start_row + index - 1, 0, #header.key, hl.symbols.pending)
  end

  table.insert(hints, "\n")
  title = "Global mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  start_row = #hints
  for index, header in ipairs(globals) do
    local line = header.key .. " " .. header.desc
    table.insert(hints, line .. "\n")
    tables.add_mark(marks, start_row + index - 1, 0, #header.key, hl.symbols.pending)
  end

  buffers.floating_buffer(vim.split(table.concat(hints, ""), "\n"), marks, "k8s_hints", { title = "Hints" })
end

--- Execute a user command and handle the response
---@param args table
function M.UserCmd(args)
  ResourceBuilder:new("k8s_usercmd"):setCmd(args):fetchAsync(function(self)
    if self.data == "" then
      return
    end
    self:splitData()
    self.prettyData = self.data

    vim.schedule(function()
      self:display("k8s_usercmd", "UserCmd")
    end)
  end)
end

return M
