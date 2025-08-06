local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local tables = require("kubectl.utils.tables")

local M = {}

--- PortForwards function retrieves port forwards and displays them in a float window.
-- @function PortForwards
-- @return nil
function M.View()
  local resource = "portforward"
  local self = manager.get_or_create(resource)
  self.buf_nr, self.win_nr = buffers.floating_dynamic_buffer("k8s_" .. resource, "Port forwards", nil, nil)
  self.data = M.getPFRows()
  self.extmarks = {}
  self.prettyData, self.extmarks = tables.pretty_print(self.data, { "ID", "TYPE", "NAME", "NS", "HOST", "PORT" })
  self
    .addHints({
      { key = "<Plug>(kubectl.delete)", desc = "Delete PF" },
      { key = "<Plug>(kubectl.browse)", desc = "Open in browser" },
    }, false, false, false)
    .displayContent(self.win_nr)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    vim.cmd.fclose()
    vim.api.nvim_input("<Plug>(kubectl.refresh)")
  end, { buffer = self.buf_nr, silent = true })
end

function M.getPFRows(type)
  local client = require("kubectl.client")
  local pfs = client.portforward_list()
  local data = {}
  for _, value in pairs(pfs) do
    local item = {
      id = { value = value.id, symbol = hl.symbols.gray },
      type = { value = value.type, symbol = hl.symbols.info },
      name = { value = value.name, symbol = hl.symbols.success },
      ns = { value = value.namespace, symbol = hl.symbols.info },
      host = { value = value.host, symbol = hl.symbols.pending },
      port = { value = value.local_port .. ":" .. value.remote_port, symbol = hl.symbols.pending },
    }
    if not type then
      table.insert(data, item)
    elseif type == value.type then
      table.insert(data, item)
    end
  end
  return data
end

function M.setPortForwards(marks, data, port_forwards)
  if not port_forwards or not data then
    return
  end

  for _, pf in ipairs(port_forwards) do
    if not pf.name or not pf.ns then
      return
    end

    for row, line in ipairs(data) do
      local col = line:find(pf.name.value, 1, true)
      local ns = line:find(pf.ns.value, 1, true)
      if col and ns then
        local mark = {
          row = row - 1,
          start_col = col + #pf.name.value - 1,
          end_col = col + #pf.name.value - 1 + 3,
          virt_text = { { " ⇄ ", hl.symbols.success } },
          virt_text_pos = "overlay",
        }
        table.insert(marks, mark)
      end
    end
  end
  return marks
end

function M.getCurrentSelection()
  return tables.getCurrentSelection(5, 6)
end

function M.OpenBrowser(host, port)
  local proto = port == "443" and "https" or "http"
  local url
  if port ~= "443" and port ~= "80" then
    url = string.format("%s://%s:%s", proto, host, port)
  else
    url = string.format("%s://%s", proto, host)
  end
  print(url)
  vim.ui.open(url)
end

return M
