--- @return string
local function get_lib_extension()
  if jit.os:lower() == "mac" or jit.os:lower() == "osx" then
    return ".dylib"
  end
  if jit.os:lower() == "windows" then
    return ".dll"
  end
  return ".so"
end

--- Get the directory containing this file, handling both Unix and Windows paths
--- @return string
local function get_script_dir()
  local source = debug.getinfo(1).source
  -- Remove leading @ if present
  source = source:gsub("^@", "")
  -- Normalize all backslashes to forward slashes (Lua handles both on Windows)
  source = source:gsub("\\", "/")
  -- Extract directory (everything up to and including the last /)
  local dir = source:match("(.*/)")
  return dir or ""
end

local script_dir = get_script_dir()
local ext = get_lib_extension()

-- Build paths to search for the native library
local paths = {}
local function add_path(relative_dir, prefix)
  table.insert(paths, script_dir .. relative_dir .. prefix .. "?" .. ext)
end

-- Standard cargo output directories (Unix and native Windows builds)
add_path("../../../../target/release/", "lib")
add_path("../../../../target/release/", "")
add_path("../../../../target/debug/", "lib")
add_path("../../../../target/debug/", "")

-- Windows gnu target directories (used by CI releases)
if jit.os:lower() == "windows" then
  add_path("../../../../target/x86_64-pc-windows-gnu/release/", "lib")
  add_path("../../../../target/x86_64-pc-windows-gnu/release/", "")
  add_path("../../../../target/x86_64-pc-windows-gnu/debug/", "lib")
  add_path("../../../../target/x86_64-pc-windows-gnu/debug/", "")
end

package.cpath = package.cpath .. ";" .. table.concat(paths, ";")

return require("kubectl_client")
