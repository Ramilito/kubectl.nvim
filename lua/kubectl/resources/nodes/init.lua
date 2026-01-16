local BaseResource = require("kubectl.resources.base_resource")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local kubectl_client = require("kubectl.client")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local resource = "nodes"

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "Node" },
  child_view = {
    name = "pods",
    predicate = function(name)
      return "spec.nodeName=" .. name
    end,
  },
  hints = {
    { key = "<Plug>(kubectl.cordon)", desc = "cordon", long_desc = "Cordon selected node" },
    { key = "<Plug>(kubectl.uncordon)", desc = "uncordon", long_desc = "UnCordon selected node" },
    { key = "<Plug>(kubectl.drain)", desc = "drain", long_desc = "Drain selected node" },
    { key = "<Plug>(kubectl.shell)", desc = "shell", long_desc = "Shell into selected node" },
  },
  headers = {
    "NAME",
    "STATUS",
    "ROLES",
    "AGE",
    "VERSION",
    "INTERNAL-IP",
    "EXTERNAL-IP",
    "OS-IMAGE",
  },
})

function M.Drain(node)
  local builder = manager.get(M.definition.resource)
  local node_def = {
    ft = "k8s_action",
    display = "Drain node: " .. node .. "?",
    resource = node,
  }
  local data = {
    { text = "grace period:", value = "-1", type = "option" },
    { text = "timeout sec:", value = "5", type = "option" },
    { text = "ignore daemonset:", value = "false", type = "flag" },
    { text = "delete emptydir data:", value = "false", type = "flag" },
    { text = "force:", value = "false", type = "flag" },
    { text = "dry run:", value = "false", type = "flag" },
  }
  if builder then
    builder.action_view(node_def, data, function(args)
      local cmd_args = {
        context = state.context["current-context"],
        node = node,
        grace = args[1].value,
        timeout = args[2].value,
        ignore_ds = args[3].value == "true" and true or false,
        delete_emptydir = args[4].value == "true" and true or false,
        force = args[5].value == "true" and true or false,
        dry_run = args[6].value == "true" and true or false,
      }
      commands.run_async("drain_node_async", cmd_args, function(ok)
        vim.schedule(function()
          vim.notify(ok, vim.log.levels.INFO)
        end)
      end)
    end)
  end
end

function M.UnCordon(node)
  local client = require("kubectl.client")
  local ok = client.uncordon_node(node)
  vim.schedule(function()
    vim.notify(ok, vim.log.levels.INFO)
  end)
end

function M.Cordon(node)
  local client = require("kubectl.client")
  local ok = client.cordon_node(node)
  vim.schedule(function()
    vim.notify(ok, vim.log.levels.INFO)
  end)
end

local function attach_session(sess, buf, win)
  local chan = vim.api.nvim_open_term(buf, {
    on_input = function(_, _, _, data)
      sess:write(data)
    end,
  })
  vim.cmd.startinsert()

  local timer = vim.uv.new_timer()
  if not timer then
    vim.notify("Timer failed to initialize", vim.log.levels.ERROR)
    return
  end
  timer:start(
    0,
    30,
    vim.schedule_wrap(function()
      repeat
        local chunk = sess:read_chunk()
        if chunk then
          vim.api.nvim_chan_send(chan, chunk)
        end
      until not chunk
      if not sess:open() then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)
  )
end

local function spawn_node_shell(title, key, config)
  local ok, sess = pcall(kubectl_client.node_shell, config)
  if not ok or sess == nil then
    vim.notify("kubectl-client error: " .. tostring(sess), vim.log.levels.ERROR)
    return
  end
  local buf, win = buffers.floating_buffer(key, title)
  state.picker_register(key, title, buffers.floating_buffer, { key, title })

  vim.api.nvim_set_current_buf(buf)
  vim.schedule(function()
    attach_session(sess, buf, win)
  end)
end

function M.Shell(node)
  local def = {
    resource = "node_shell",
    ft = "k8s_action",
    display = "Shell into node: " .. node .. "?",
  }

  local builder = manager.get_or_create(def.resource)

  local data = {
    { text = "namespace:", value = "default", type = "option" },
    { text = "image:", value = "busybox:latest", type = "option" },
    { text = "cpu limit:", value = "", type = "option" },
    { text = "mem limit:", value = "", type = "option" },
  }

  builder.action_view(def, data, function(args)
    vim.schedule(function()
      local config = {
        node = node,
        namespace = args[1].value,
        image = args[2].value,
        cpu_limit = args[3].value ~= "" and args[3].value or nil,
        mem_limit = args[4].value ~= "" and args[4].value or nil,
      }
      spawn_node_shell(string.format("node-shell | %s", node), "k8s_node_shell", config)
    end)
  end)
end

return M
