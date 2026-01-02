local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local definition = require("kubectl.views.namespace.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local resource = "namespaces"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    title = "Namespaces",
    gvk = { g = "", v = "v1", k = "Namespace" },
    headers = {
      "NAME",
      "STATUS",
      "AGE",
    },
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.tab)", desc = "next" },
      { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
      { key = "<Plug>(kubectl.quit)", desc = "close" },
    },
    panes = {
      { title = "Namespaces", prompt = true },
    },
  },
  namespaces = { "All" },
}

function M.View()
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.view_framed(M.definition)

  local buf = builder.buf_nr

  -- Set up prompt callback
  vim.fn.prompt_setcallback(buf, function(input)
    input = vim.trim(input)
    if vim.tbl_contains(M.namespaces, input) or input == "" then
      M.changeNamespace(input)
    else
      vim.schedule(function()
        vim.notify("Not a valid namespace", vim.log.levels.ERROR)
      end)
    end
    vim.cmd("stopinsert")
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.fclose()
  end)

  vim.cmd("startinsert")

  commands.run_async("start_reflector_async", { gvk = M.definition.gvk, namespace = nil }, function(_, err)
    if err then
      return
    end
    commands.run_async("get_all_async", { gvk = M.definition.gvk, nil }, function(data, _)
      builder.data = data
      builder.decodeJson()
      vim.schedule(function()
        builder.process(definition.processRow, true).prettyPrint()
        builder.displayContent(builder.win_nr)
        buffers.fit_framed_to_content(builder.frame, 1)

        local list = { { name = "All" } }
        for _, value in ipairs(builder.processedData) do
          if value.name.value then
            table.insert(M.namespaces, value.name.value)
            table.insert(list, { name = value.name.value })
          end
        end
        completion.with_completion(buf, list)

        vim.api.nvim_buf_set_keymap(buf, "n", "<cr>", "", {
          noremap = true,
          callback = function()
            local line = vim.api.nvim_get_current_line()
            local current_word = vim.split(line, "%s%s+")[1]

            vim.cmd("startinsert")
            vim.schedule(function()
              vim.api.nvim_put({ current_word }, "c", true, true)
              vim.api.nvim_input("<cr>")
            end)
          end,
        })
      end)
    end)
  end)
end

--- Returns a list of namespaces
--- @return string[]
function M.listNamespaces()
  local client = require("kubectl.client")
  local payload = vim.json.encode({ gvk = M.definition.gvk, nil }, { luanil = { object = true, array = true } })
  local output = vim.json.decode(client.get_all(payload), { luanil = { object = true, array = true } })
  local ns = {}
  for _, value in ipairs(output) do
    table.insert(ns, value.metadata.name)
  end
  return ns
end

function M.changeNamespace(name)
  if name == "" then
    name = "All"
  end
  state.ns = name
end

return M
