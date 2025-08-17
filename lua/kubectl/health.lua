local health = {}

local H = vim.health
function health.check()
  H.start("Kubectl.nvim health report")
  local kubectl = require("kubectl")
  local config = require("kubectl.config")
  if kubectl.did_setup then
    H.ok("setup called")
  else
    H.error("setup not called")
  end

  if config.config_did_setup then
    H.ok("config setup called")
  else
    H.error("config setup not called")
  end

  health.report_download()

  H.info("Health check completed")
end

function health.report_download()
  local ok, system = pcall(require, "blink.download.system")
  if not ok then
    H.error("Blink.download not available")
  end
  local download_config = require("blink.cmp.config").fuzzy.prebuilt_binaries

  local get_linux_libc_sync = function()
    local _, process = pcall(function()
      return vim.system({ "cc", "-dumpmachine" }, { text = true }):wait()
    end)
    if process and process.code == 0 then
      -- strip whitespace
      local stdout = process.stdout:gsub("%s+", "")
      local triple_parts = vim.fn.split(stdout, "-")
      if triple_parts[4] ~= nil then
        return triple_parts[4]
      end
    end

    local _, is_alpine = pcall(function()
      return vim.uv.fs_stat("/etc/alpine-release")
    end)
    if is_alpine then
      return "musl"
    end
    return "gnu"
  end

  local get_triple = function()
    if download_config.force_system_triple then
      return download_config.force_system_triple
    end

    local os, arch = system.get_info()
    local triples = system.triples[os]
    if triples == nil then
      return
    end

    if os == "linux" then
      if vim.fn.has("android") == 1 then
        return triples.android
      end

      local triple = triples[arch]
      if type(triple) ~= "function" then
        return triple
      end
      return triple(get_linux_libc_sync())
    else
      return triples[arch]
    end
  end

  local system_triple = get_triple()
  if system_triple then
    H.ok("Your system is supported by pre-built binaries (" .. system_triple .. ")")
  else
    H.warn(
      "Your system is not supported by pre-built binaries. You must run cargo build --release via your package manager with rust nightly. See the README for more info."
    )
  end
end

return health
