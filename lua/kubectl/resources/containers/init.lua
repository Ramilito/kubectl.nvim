local client = require("kubectl.client")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.resources.containers.definition")
local manager = require("kubectl.resource_manager")
local pod_view = require("kubectl.resources.pods")
local queue = require("kubectl.event_queue")
local terminal = require("kubectl.utils.terminal")

local resource = "containers"

local M = {
  selection = {},
  definition = {
    resource = resource,
    ft = "k8s_" .. resource,
    title = "Containers",
    gvk = { g = pod_view.definition.gvk.g, v = pod_view.definition.gvk.v, k = pod_view.definition.gvk.k },
    headers = {
      "NAME",
      "IMAGE",
      "READY",
      "STATE",
      "TYPE",
      "RESTARTS",
      "PORTS",
      "CPU",
      "MEM",
      "CPU/RL",
      "MEM/RL",
      "%CPU/R",
      "%CPU/L",
      "%MEM/R",
      "%MEM/L",
      "AGE",
    },
    processRow = definition.processRow,
    cmd = "get_container_table_async",
    hints = {
      { key = "<Plug>(kubectl.logs)", desc = "logs" },
      { key = "<Plug>(kubectl.debug)", desc = "debug" },
      { key = "<Plug>(kubectl.select)", desc = "exec" },
      { key = "<Plug>(kubectl.select_fullscreen)", desc = "exec" },
    },
    panes = {
      { title = "Containers" },
    },
  },
  log_since = config.options.logs.since,
  show_previous = "false",
}

function M.selectContainer(name)
  M.selection = name
end

local function draw(builder, pod, ns)
  local gvk = M.definition.gvk
  commands.run_async(M.definition.cmd, { gvk = gvk, name = pod, namespace = ns }, function(result)
    builder.data = result
    builder.decodeJson()
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(builder.win_nr) then
        return
      end
      builder
        .process(M.definition.processRow, true)
        .sort()
        .prettyPrint()
        .addDivider(false)
        .displayContent(builder.win_nr)
    end)
  end)
end

function M.View(pod, ns)
  M.definition.display_name = "pods | " .. pod .. " | " .. ns
  local builder = manager.get_or_create(M.definition.resource)
  builder.view_framed(M.definition, {
    recreate_func = M.View,
    recreate_args = { pod, ns },
  })

  draw(builder, pod, ns)

  queue.register(pod_view.definition.gvk.k, builder.buf_nr, function(payload)
    local ev = vim.json.decode(payload)
    if ev.metadata.name == pod_view.selection.pod then
      draw(builder, pod_view.selection.pod, pod_view.selection.ns)
    end
  end)
end

function M.exec(pod, ns, is_fullscreen)
  if config.options.terminal_cmd then
    local args = { "exec", "-it", pod, "-n", ns, "-c", M.selection, "--", "/bin/sh" }
    local cmd = commands.configure_command("kubectl", {}, args)
    vim.fn.jobstart(config.options.terminal_cmd .. " " .. table.concat(cmd.args, " "))
    return
  end

  terminal.spawn_terminal(
    string.format("%s | %s: %s | %s", "container", pod, M.selection, ns),
    "k8s_exec",
    client.exec,
    is_fullscreen,
    ns,
    pod,
    M.selection,
    { "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh" }
  )
end

function M.debug(pod, ns, is_fullscreen)
  local def = {
    resource = "kubectl_debug",
    ft = "k8s_action",
    display = "Debug: " .. pod .. " - " .. M.selection .. " ?",
  }

  local builder = manager.get_or_create(def.resource)

  local data = {
    { text = "name:", value = M.selection .. "-debug", type = "option" },
    { text = "image:", value = "busybox", type = "option" },
  }

  builder.action_view(def, data, function(args)
    local cmd_args = {
      name = args[1].value,
      image = args[2].value,
    }
    terminal.spawn_terminal(
      cmd_args.name,
      "k8s_debug",
      client.debug,
      is_fullscreen,
      ns,
      pod,
      cmd_args.image,
      M.selection
    )
  end)
end

return M
