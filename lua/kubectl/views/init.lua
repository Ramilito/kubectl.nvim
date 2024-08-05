local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.definition")
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
    { key = "<C-f>", desc = "Filter on a phrase" },
    { key = "<C-n>", desc = "Change namespace" },
    { key = "<bs> ", desc = "Go up a level" },
    { key = "<gD> ", desc = "Delete resource" },
    { key = "<gP> ", desc = "Port forwards" },
    { key = "<gs> ", desc = "Sort column" },
    { key = "<ge> ", desc = "Edit resource" },
    { key = "<gr> ", desc = "Refresh view" },
    { key = "<0>  ", desc = "Root" },
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

function M.Aliases()
  local getHeaders = function()
    return { "NAME" }
  end
  ResourceBuilder:new("cmd"):setCmd({ "api-resources", "-o", "name", "--cached=true" }):fetchAsync(function(self)
    self
      :splitData()
      :decodeJson()
      :process(function(rows)
        local data = {}
        for _, row in ipairs(rows) do
          table.insert(data, {
            name = row,
          })
        end
        return data
      end)
      :sort()
      :prettyPrint(getHeaders)
    vim.schedule(function()
      self:displayFloat("k8s_aliases", "Aliases", "", true)
    end)
  end)
end

--- PortForwards function retrieves port forwards and displays them in a float window.
-- @function PortForwards
-- @return nil
function M.PortForwards()
  local pfs = {}
  pfs = definition.getPortForwards(pfs, false, "all")

  local builder = ResourceBuilder:new("Port forward")

  local data = {}
  builder.extmarks = {}
  for _, value in ipairs(pfs) do
    table.insert(data, {
      pid = { value = value.pid, symbol = hl.symbols.gray },
      type = { value = value.type, symbol = hl.symbols.info },
      resource = { value = value.resource, symbol = hl.symbols.success },
      port = { value = value.port, symbol = hl.symbols.pending },
    })
  end

  builder.prettyData, builder.extmarks = tables.pretty_print(data, { "PID", "TYPE", "RESOURCE", "PORT" })
  builder
    :displayFloat("k8s_port_forwards", "Port forwards", "", true)
    :addHints({ { key = "<gk>", desc = "Kill PF" } }, false, false, false)
    :displayFloat("k8s_port_forwards", "Port forwards", "", true)

  local group = "k8s_port_forwards"
  vim.api.nvim_create_augroup(group, { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
    group = group,
    buffer = builder.buf_nr,
    callback = function()
      vim.api.nvim_input("gr")
    end,
  })
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
