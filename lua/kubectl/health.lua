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
		return
  end

  local system_triple = system.get_triple_sync()
  if system_triple then
    H.ok("Your system is supported by pre-built binaries (" .. system_triple .. ")")
  else
    H.warn(
      --luacheck: ignore
      "Your system is not supported by pre-built binaries. You must run cargo build --release via your package manager with rust nightly. See the README for more info."
    )
  end
end

return health
