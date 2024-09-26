local state = require("kubectl.state")
local M = {}

--- Replace placeholders in the argument string
---@param arg string
---@return string
local function replacePlaceholders(arg)
  arg = arg:gsub("{{BASE}}", state.getProxyUrl())
  if state.ns and state.ns ~= "All" then
    arg = arg:gsub("{{NAMESPACE}}", string.format("namespaces/%s/", state.ns))
  else
    arg = arg:gsub("{{NAMESPACE}}", "")
  end
  return arg
end

--- Add headers to the argument list based on content type
---@param args string[]
---@param contentType? string
---@return string[]
function M.addHeaders(args, contentType)
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

  local selectedHeaders = headers[contentType] or headers.default
  for i = #selectedHeaders, 1, -1 do
    table.insert(args, 1, selectedHeaders[i])
  end

  table.insert(args, 1, "-sS")
  table.insert(args, 1, "GET")
  table.insert(args, 1, "-X")
  return args
end

--- Build the argument list by replacing placeholders
---@param args string[]
---@return string[]
function M.build(args)
  local parsed_args = {}
  for i, arg in ipairs(args) do
    parsed_args[i] = replacePlaceholders(arg)
  end

  return parsed_args
end

--- Break URL to Query parameters and base URL
---@param url string Full URL
---@param as_string? boolean Return query parameters as string (default: false)
---@param check_https? boolean Check if the URL starts with http:// or https:// (default: true)
---@return string|nil Base URL
---@return string|table|nil Base Query parameters
function M.breakUrl(url, as_string, check_https)
  if type(as_string) ~= "boolean" then
    as_string = false
  end
  if type(check_https) ~= "boolean" then
    check_https = true
  end
  local ret = { url = nil, query = as_string and nil or {} }
  local params = {}
  if check_https and not url:match("^https?://") then
    return nil, nil
  end
  local url_no_query_params, query_params = url:match("([^?]+)%??(.*)")

  ret["url"] = url_no_query_params or url

  if query_params and query_params ~= nil then
    if as_string then
      ret["query"] = query_params
    else
      for key, value in query_params:gmatch("([^&=]+)=([^&=]+)") do
        params[key] = value
      end
      ret["query"] = params
    end
  end

  return ret["url"], ret["query"]
end

return M
