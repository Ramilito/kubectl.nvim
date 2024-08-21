local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local string_utils = require("kubectl.utils.string")
local viewsTable = require("kubectl.utils.viewsTable")

local M = {}

---@param port_forwards {pid: string, type: string, resource: string, port: string} @Array of port forwards
---@param async boolean @Indicates whether the function should run asynchronously
---@param kind "pods"|"svc"|"all" @What types we want to retrieve
---@return table[] @Returns the modified array of port forwards
function M.getPFData(port_forwards, async, kind)
  if vim.fn.has("win32") == 1 then
    return port_forwards
  end

  local function parse(data)
    if not data then
      return
    end

    for _, line in ipairs(vim.split(data, "\n")) do
      local pid = string_utils.trim(line):match("^(%d+)")
      local resource_type = line:match("%s(pods)/") or line:match("%s(svc)/")

      local resource, port
      if kind == "pods" then
        resource, port = line:match("pods/([^%s]+)%s+(%d+:%d+)$")
      elseif kind == "svc" then
        resource, port = line:match("svc/([^%s]+)%s+(%d+:%d+)$")
      elseif kind == "all" then
        resource, port = line:match("/([^%s]+)%s+(%d+:%d+)$")
      end

      if resource and port then
        table.insert(port_forwards, { pid = pid, type = resource_type, resource = resource, port = port })
      end
    end
  end

  local args = "ps -eo pid,args | grep '[k]ubectl port-forward'"
  if async then
    commands.shell_command_async("sh", { "-c", args }, function(data)
      parse(data)
    end)
  else
    local data = commands.shell_command("sh", { "-c", args })
    parse(data)
  end

  return port_forwards
end

function M.getPFRows(pfs)
  local data = {}
  for _, value in ipairs(pfs) do
    table.insert(data, {
      pid = { value = value.pid, symbol = hl.symbols.gray },
      type = { value = value.type, symbol = hl.symbols.info },
      resource = { value = value.resource, symbol = hl.symbols.success },
      port = { value = value.port, symbol = hl.symbols.pending },
    })
  end
  return data
end

function M.setPortForwards(marks, data, port_forwards)
  if not port_forwards then
    return
  end
  for _, pf in ipairs(port_forwards) do
    if not pf.resource then
      return
    end
    for row, line in ipairs(data) do
      local col = line:find(pf.resource, 1, true)

      if col then
        local mark = {
          row = row - 1,
          start_col = col + #pf.resource - 1,
          end_col = col + #pf.resource - 1 + 3,
          virt_text = { { " ⇄ ", hl.symbols.success } },
          virt_text_pos = "overlay",
        }
        table.insert(marks, #marks, mark)
      end
    end
  end
  return marks
end

function M.on_prompt_input(input)
  if input == "" then
    return
  end
  local parsed_input = string.lower(string_utils.trim(input))
  local supported_view = nil
  for k, v in pairs(viewsTable) do
    if find.is_in_table(v, parsed_input, true) then
      supported_view = k
    end
  end

  if supported_view then
    local ok, view = pcall(require, "kubectl.views." .. supported_view)
    if ok then
      vim.schedule(function()
        pcall(view.View)
      end)
    end
  else
    vim.schedule(function()
      local view = require("kubectl.views.fallback")
      view.View(nil, parsed_input)
    end)
  end
end

--- Decode a JSON string
--- @param string string The JSON string to decode
--- @return table|nil result The decoded table or nil if decoding fails
local decode = function(string)
  local success, result = pcall(vim.json.decode, string)
  if success then
    return result
  else
    vim.notify("Error: api-resources unavailable", vim.log.levels.ERROR)
  end
end

function M.process_apis(group_name, group_version, group_data, cached_api_resources)
  local group_resources = decode(group_data) or { resources = {} }
  for _, resource in ipairs(group_resources.resources) do
    repeat
      if string.find(resource.name, "/status") then
        do
          break
        end
      end
      local resource_name = resource.name .. "." .. group_name
      local resource_url = string.format("{{BASE}}/apis/%s/{{NAMESPACE}}%s?pretty=false", group_version, resource.name)
      cached_api_resources.values[resource_name] = {
        name = resource.name,
        url = resource_url,
      }
      require("kubectl.state").sortby[resource_name] = { mark = {}, current_word = "", order = "asc" }
      cached_api_resources.shortNames[resource.name] = resource_name
      if resource.singularName then
        cached_api_resources.shortNames[resource.singularName] = resource_name
      end
      if resource.shortNames then
        for _, shortName in ipairs(resource.shortNames) do
          cached_api_resources.shortNames[shortName] = resource_name
        end
      end
    until true
  end
end

function M.process_api_groups(apis, cached_api_resources)
  for _, group in ipairs(apis.groups) do
    repeat
      local group_name = group.name
      local group_version = group.preferredVersion.groupVersion
      -- check if name contains 'metrics.k8s.io' and skip
      if string.find(group_name, "metrics.k8s.io") then
        do
          break
        end
      end
      commands.shell_command_async("kubectl", { "get", "--raw", "/apis/" .. group_version }, function(group_data)
        M.process_apis(group_name, group_version, group_data, cached_api_resources)
      end)
    until true
  end
end

return M
