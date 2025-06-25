local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
-- local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local views = require("kubectl.views")

local M = {
  definition = {
    resource = "kubectl_filter_label",
    display = "Filter on labels",
    ft = "k8s_filter_label",
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.tab)", desc = "next" },
      { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
    },
    notes = "Select none to clear existing filters.",
  },
}

function M.filter_label_new()
  local buf_name = vim.api.nvim_buf_get_var(0, "buf_name")

  local instance = manager.get(buf_name)
  if not instance then
    return
  end
  local view, resource_definition = views.view_and_definition(instance.resource)
  local name, ns = view.getCurrentSelection()
  if not name then
    return
  end
  M.definition.ns = ns

  local builder = manager.get_or_create(M.definition.resource)
  commands.run_async("get_single_async", {
    kind = resource_definition.gvk.k,
    namespace = ns,
    name = name,
    output = "Json",
  }, function(data)
    if not data then
      return
    end

    builder.header = { data = {}, marks = {} }
    builder.extmarks = {}
    builder.data = data
    builder.decodeJson()
    local lines = {}
    local labels = builder.data.metadata.labels
    for key, value in pairs(labels) do
      -- add label k=v
      table.insert(lines, key .. "=" .. value)

      -- add checkbox
      table.insert(builder.extmarks, {
        row = #lines - 1,
        start_col = 0,
        virt_text = { { "[ ]" .. " ", hl.symbols.header } },
        virt_text_pos = "inline",
        right_gravity = false,
      })

      -- add highlight extmark to key
      table.insert(builder.extmarks, {
        row = #lines - 1,
        start_col = 0,
        end_col = #key,
        hl_group = hl.symbols.info,
      })
    end

    local win_config
    vim.schedule(function()
      builder.buf_nr, win_config = buffers.confirmation_buffer(M.definition.display, M.definition.ft, function(confirm)
        if confirm then
          print(vim.inspect(win_config))
        end
      end)

      -- add hints
      builder.addHints(M.definition.hints, false, false)

      -- add notes with extmark
      table.insert(builder.header.data, M.definition.notes)
      table.insert(builder.header.marks, {
        row = #builder.header.data - 1,
        start_col = 0,
        end_col = #builder.header.data[#builder.header.data],
        hl_group = hl.symbols.gray,
      })

      -- add divider
      tables.generateDividerRow(builder.header.data, builder.header.marks)

      builder.data = lines
      table.insert(builder.data, "")
      table.insert(builder.data, "")
      table.insert(builder.data, "")

      local confirmation = "[y]es [n]o"
      local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
      table.insert(builder.extmarks, {
        row = #builder.data - 1,
        start_col = 0,
        virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
        virt_text_pos = "inline",
      })
      builder.displayContentRaw()
    end)

    -- local action_data = {}
    -- for key, value in pairs(labels) do
    --   table.insert(action_data, {
    --     text = key .. "=" .. value,
    --     value = "[ ]",
    --     type = "positional",
    --     options = { "[x]", "[ ]" },
    --   })
    -- end
    --
    -- builder.data = {}
    -- vim.schedule(function()
    --   builder.action_view(def, action_data, function(args)
    --     local selection = {}
    --     for _, item in ipairs(args) do
    --       if item.value == "[x]" then
    --         table.insert(selection, item.text)
    --       end
    --     end
    --     state.filter_label = selection
    --   end)
    -- end)
  end)
end

function M.Draw()
  local builder = manager.get("action_view")
  if not builder then
    return
  end

  builder.displayContentRaw()
  vim.cmd([[syntax match KubectlPending /.*/]])
end

return M
