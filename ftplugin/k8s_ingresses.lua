local api = vim.api
local ResourceBuilder = require("kubectl.resourcebuilder")
local ingresses_view = require("kubectl.views.ingresses")
local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")

--- Set key mappings for the buffer
local function set_keymap(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      overview_view.View()
    end,
  })
  api.nvim_buf_set_keymap(bufnr, "n", "gx", "", {
    noremap = true,
    silent = true,
    desc = "Open host in browser",
    callback = function()
      local name, ns = ingresses_view.getCurrentSelection()
      ResourceBuilder:new("ingress_host")
        :setCmd({ "get", "ingress", name, "-n", ns, "-o", "json" }, "kubectl")
        :fetchAsync(function(self)
          self:decodeJson()
          local data = self.data

          -- determine port
          local port = ""
          if
            data.spec.rules
            and data.spec.rules[1]
            and data.spec.rules[1].http
            and data.spec.rules[1].http.paths
            and data.spec.rules[1].http.paths[1]
            and data.spec.rules[1].http.paths[1].backend
          then
            local backend = data.spec.rules[1].http.paths[1].backend
            port = backend.service.port.number or backend.servicePort or "80"
          end

          -- determine host
          local host = ""
          if data.spec.rules and data.spec.rules[1] and data.spec.rules[1].host then
            host = data.spec.rules[1].host
          else
            if data.status and data.status.loadBalancer and data.status.loadBalancer.ingress then
              local ingress = data.status.loadBalancer.ingress[1]
              if ingress.hostname then
                host = ingress.hostname
              elseif ingress.ip then
                host = ingress.ip
              end
            else
              return
            end
          end
          local proto = port == "443" and "https" or "http"
          if port ~= "443" and port ~= "80" then
            port = ":" .. port
          end
          local final_url = string.format("%s://%s%s", proto, host, port)
          vim.notify("Opening " .. final_url)
          vim.ui.open(final_url)
        end)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymap(0)
  if not loop.is_running() then
    loop.start_loop(ingresses_view.Draw)
  end
end

init()
