local health = {}

local H = vim.health

function health.check()
  H.start("Kubectl.nvim")

  health.report_setup()
  health.report_neovim()
  health.report_native_library()
  health.report_kubeconfig()
  health.report_runtime()
end

function health.report_setup()
  local kubectl = require("kubectl")
  local config = require("kubectl.config")

  if kubectl.did_setup then
    H.ok("Setup called")
  else
    H.error("Setup not called - run require('kubectl').setup()")
  end

  if config.config_did_setup then
    H.ok("Config initialized")
  else
    H.error("Config not initialized")
  end
end

function health.report_neovim()
  local v = vim.version()
  local version_str = string.format("%d.%d.%d", v.major, v.minor, v.patch)

  if v.major > 0 or (v.major == 0 and v.minor >= 11) then
    H.ok("Neovim version: " .. version_str)
  else
    H.error("Neovim 0.11+ required, found: " .. version_str)
  end
end

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

function health.report_native_library()
  local platform = string.format("%s/%s", jit.os, jit.arch)
  local extension = get_lib_extension()

  -- Check if blink.download can detect system triple
  local system_triple = nil
  local blink_ok, system = pcall(require, "blink.download.system")
  if blink_ok then
    system_triple = system.get_triple_sync()
  end

  -- Check binary file existence (release and debug builds)
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1).source:match("@?(.*)"), ":h:h:h")
  local binary_paths = {
    plugin_root .. "/target/release/libkubectl_client" .. extension,
    plugin_root .. "/target/release/kubectl_client" .. extension,
    plugin_root .. "/target/debug/libkubectl_client" .. extension,
    plugin_root .. "/target/debug/kubectl_client" .. extension,
  }

  local found_binary = nil
  for _, path in ipairs(binary_paths) do
    if vim.uv.fs_stat(path) then
      found_binary = path
      break
    end
  end

  if found_binary then
    if system_triple then
      H.ok(string.format("Native binary found (%s, %s)", platform, system_triple))
    else
      H.ok(string.format("Native binary found (%s)", platform))
    end
  else
    H.error(string.format("Native binary not found (%s)", platform))
    H.info(string.format("Expected: libkubectl_client%s in target/release/ or target/debug/", extension))

    -- Provide guidance based on system support
    if blink_ok and system_triple then
      H.info("System triple: " .. system_triple .. " - pre-built binaries available")
      H.info("Try running :Lazy build kubectl.nvim or reinstalling the plugin")
    elseif blink_ok then
      H.warn("System not supported by pre-built binaries - requires manual build")
      H.info("Run: cargo build --release (requires Rust nightly)")
    else
      H.info("Install blink.download for automatic binary management")
    end
  end
end

function health.report_kubeconfig()
  -- Check KUBECONFIG env or default path
  local kubeconfig = os.getenv("KUBECONFIG") or (os.getenv("HOME") .. "/.kube/config")
  local paths = vim.split(kubeconfig, ":", { plain = true })

  local found_any = false
  for _, path in ipairs(paths) do
    if vim.fn.filereadable(path) == 1 then
      found_any = true
      break
    end
  end

  if found_any then
    if #paths == 1 then
      H.ok("Kubeconfig: " .. paths[1])
    else
      H.ok(string.format("Kubeconfig: %d files configured", #paths))
    end
  else
    H.error("Kubeconfig not found: " .. kubeconfig)
    return
  end

  -- Try to get current context from kubeconfig using native library
  local ok, mod = pcall(require, "kubectl_client")
  if ok then
    local config_ok, config_json = pcall(mod.get_config)
    if config_ok and config_json then
      local config = vim.json.decode(config_json)
      if config and config["current-context"] then
        H.ok("Current context: " .. config["current-context"])
      else
        H.warn("Current context: not set in kubeconfig")
      end
    else
      H.warn("Current context: unable to read kubeconfig")
    end
  else
    H.warn("Current context: native library not loaded")
  end
end

function health.report_runtime()
  local kubectl = require("kubectl")

  -- Check if plugin has been opened (runtime initialized)
  if not kubectl.is_open then
    H.info("Runtime: not initialized (open plugin to connect)")
    return
  end

  local state = require("kubectl.state")

  -- Context from runtime
  local context = state.context and state.context["current-context"]
  if context then
    H.ok("Active context: " .. context)
  end

  -- Namespace
  local ns = state.ns
  if ns and ns ~= "" then
    H.ok("Namespace: " .. ns)
  else
    H.ok("Namespace: All")
  end

  -- Livez status
  if state.livez then
    if state.livez.ok == true then
      local age = os.time() - (state.livez.time_of_ok or os.time())
      H.ok(string.format("API server: healthy (checked %ds ago)", age))
    elseif state.livez.ok == false then
      local age = os.time() - (state.livez.time_of_ok or os.time())
      H.error(string.format("API server: unhealthy (last ok %ds ago)", age))
    else
      H.info("API server: checking...")
    end
  end

  -- Version skew
  local versions = state.versions
  if versions and (versions.client.minor ~= 0 or versions.server.minor ~= 0) then
    local client_str = string.format("%d.%d", versions.client.major, versions.client.minor)
    local server_str = string.format("%d.%d", versions.server.major, versions.server.minor)
    local skew = math.abs(versions.client.minor - versions.server.minor)

    if skew <= 1 then
      H.ok(string.format("Versions: client %s, server %s", client_str, server_str))
    else
      H.warn(string.format("Version skew: client %s, server %s (%d minor versions)", client_str, server_str, skew))
    end
  end

  -- Cache status
  local cache = require("kubectl.cache")
  if cache.loading then
    H.info("API resources: loading...")
  else
    local resources = cache.cached_api_resources and cache.cached_api_resources.values
    local count = resources and vim.tbl_count(resources) or 0
    if count > 0 then
      H.ok(string.format("API resources: %d cached", count))
    end
  end
end

return health
