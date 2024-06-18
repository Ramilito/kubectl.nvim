local state = require("kubectl.state")
local M = {}

local function replacePlaceholders(arg)
  arg = arg:gsub("{{BASE}}", state.getProxyUrl())
  if state.ns and state.ns ~= "All" then
    arg = arg:gsub("{{NAMESPACE}}", string.format("namespaces/%s/", state.ns))
  else
    arg = arg:gsub("{{NAMESPACE}}", "")
  end
  return arg
end

function M.build(args, contentType)
  local headers = {
    yaml = {
      "-H",
      "Accept: application/yaml",
      "-H",
      "Content-Type: application/yaml",
    },
    ["text/html"] = {
      "-H",
      "Accept: application/yaml",
      "-H",
      "Content-Type: text/plain",
    },
    default = {
      "-H",
      "Content-Type: application/json",
    },
  }

  for i, arg in ipairs(args) do
    args[i] = replacePlaceholders(arg)
  end

  local selectedHeaders = headers[contentType] or headers.default
  for i = #selectedHeaders, 1, -1 do
    table.insert(args, 1, selectedHeaders[i])
  end

  table.insert(args, 1, "-sS")
  table.insert(args, 1, "GET")
  table.insert(args, 1, "-X")

  return args
end

return M
