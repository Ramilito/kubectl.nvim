local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local splash = require("kubectl.splash")

local resource = "contexts"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    url = { "config", "view", "-ojson" },
    title = "Contexts",
    headers = {
      "NAME",
      "NAMESPACE",
      "CLUSTER",
      "USER",
    },
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.quit)", desc = "close" },
    },
    panes = {
      { title = "Contexts", prompt = true },
    },
  },
  contexts = {},
}

function M.View()
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.view_framed(M.definition)

  local buf = builder.buf_nr
  local win = builder.win_nr

  -- Set up prompt callback
  vim.fn.prompt_setcallback(buf, function(input)
    input = vim.trim(input)
    if vim.tbl_contains(M.contexts, input) or input == "" then
      M.change_context(input)
    else
      vim.schedule(function()
        vim.notify("Not a valid context", vim.log.levels.ERROR)
      end)
    end
    vim.cmd("stopinsert")
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.fclose()
  end)

  vim.cmd("startinsert")

  commands.run_async("get_config_async", {}, function(data)
    builder.data = data
    builder.decodeJson()

    vim.schedule(function()
      builder.process(M.processRow, true).prettyPrint().displayContent(win)
      builder.fitToContent(1)

      M.contexts = {}
      for _, value in ipairs(builder.processedData) do
        if value.name.value then
          table.insert(M.contexts, value.name.value)
        end
      end

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
end

--- Returns a list of context-names
--- @return string[]
function M.list_contexts()
  if #M.contexts > 0 then
    return M.contexts
  end

  local client = require("kubectl.client")
  local self = manager.get_or_create(M.definition.resource)
  self.data = client.get_config()
  self.decodeJson()

  M.contexts = {}
  for _, context in ipairs(self.data.contexts) do
    if context.name then
      table.insert(M.contexts, context.name)
    end
  end

  return M.contexts
end

--- Change context and reset state
--- @param cmd string
function M.change_context(cmd)
  local loop = require("kubectl.utils.loop")
  loop.stop_all()

  M.clear_buffers(cmd)

  splash.show()

  vim.schedule(function()
    local state = require("kubectl.state")
    state.context["current-context"] = cmd

    local cache = require("kubectl.cache")
    cache.clear_cache()

    local lineage_graph = require("kubectl.views.lineage.graph")
    lineage_graph.clear_lineage_cache()

    local header = require("kubectl.views.header")
    header.Close()

    splash.status("State reset ✔ ")
    local client = require("kubectl.client")
    client.set_implementation(function(ok)
      if ok then
        vim.schedule(function()
          state.setup()
          cache.loading = false
          cache.LoadFallbackData()
          local lineage = require("kubectl.views.lineage")
          lineage.loaded = false
          vim.api.nvim_exec_autocmds("User", {
            pattern = "K8sContextChanged",
            data = { context = cmd },
          })

          header.View()
          splash.done("Context: " .. (state.context["current-context"] or ""))
        end)
      else
        splash.fail("Failed to load context")
      end
    end)
  end)
end

function M.clear_buffers(context)
  local prefix = "k8s_"

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.startswith(vim.bo[buf].filetype, prefix)
      and vim.fn.bufwinnr(buf) == -1
    then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- Clearing all buffers
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" or cfg.relative == nil then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_loaded(buf) then
        if vim.startswith(vim.bo[buf].filetype, prefix) then
          vim.schedule(function()
            pcall(vim.api.nvim_set_option_value, "winbar", "", { scope = "local", win = win })
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Loading new context: " .. context })
          end)
        end
      end
    end
  end
end

function M.processRow(rows)
  local data = {}
  -- rows.contexts
  for _, row in ipairs(rows.contexts) do
    local context = {
      name = { value = row.name, symbol = hl.symbols.success },
      namespace = row.context.namespace or "",
      cluster = row.context.cluster or "",
      user = row.context.user or "",
    }

    table.insert(data, context)
  end

  return data
end

return M
