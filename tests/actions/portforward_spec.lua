describe("actions.portforward", function()
  local portforward
  local mock_hl

  -- Helper to set up mocks and reload the module
  local function setup_mocks(spec_data, opts)
    opts = opts or {}

    -- Mock highlight module
    mock_hl = {
      symbols = {
        pending = "pending_symbol",
        success = "success_symbol",
      },
    }
    package.loaded["kubectl.actions.highlight"] = mock_hl

    -- Mock tables module - capture ports passed to pretty_print
    local captured_ports
    package.loaded["kubectl.utils.tables"] = {
      pretty_print = function(ports)
        captured_ports = ports
        return {}, {}
      end,
    }

    -- Create mock_builder with configurable action_view
    -- Use a wrapper so we can change action_view after setup
    -- Note: production code calls builder.action_view(def, pf_data, callback) without self
    local action_view_fn = opts.action_view or function() end
    local mock_builder = {
      data = nil,
      decodeJson = function() end,
      action_view = function(def, pf_data, callback)
        return action_view_fn(def, pf_data, callback)
      end,
      set_action_view = function(fn)
        action_view_fn = fn
      end,
    }

    -- If get_or_create is provided, use it; otherwise use mock_builder
    if opts.get_or_create then
      package.loaded["kubectl.resource_manager"] = {
        get_or_create = opts.get_or_create,
      }
    else
      package.loaded["kubectl.resource_manager"] = {
        get_or_create = function()
          return mock_builder
        end,
      }
    end

    -- Mock commands module
    package.loaded["kubectl.actions.commands"] = {
      run_async = opts.run_async or function(_, _, callback)
        callback(spec_data)
      end,
    }

    -- Reload portforward module
    package.loaded["kubectl.actions.portforward"] = nil
    portforward = require("kubectl.actions.portforward")

    return {
      get_captured_ports = function()
        return captured_ports
      end,
      mock_builder = mock_builder,
    }
  end

  before_each(function()
    -- Clear module cache
    package.loaded["kubectl.actions.portforward"] = nil
    package.loaded["kubectl.actions.commands"] = nil
    package.loaded["kubectl.actions.highlight"] = nil
    package.loaded["kubectl.resource_manager"] = nil
    package.loaded["kubectl.utils.tables"] = nil
    package.loaded["kubectl.client"] = nil

    -- Mock highlight module
    mock_hl = {
      symbols = {
        pending = "pending_symbol",
        success = "success_symbol",
      },
    }
    package.loaded["kubectl.actions.highlight"] = mock_hl

    -- Mock commands module
    package.loaded["kubectl.actions.commands"] = {
      run_async = function() end,
    }

    -- Mock resource_manager module
    package.loaded["kubectl.resource_manager"] = {
      get_or_create = function()
        return {
          data = {},
          decodeJson = function() end,
          action_view = function() end,
        }
      end,
    }

    -- Mock tables module
    package.loaded["kubectl.utils.tables"] = {
      pretty_print = function()
        return {}, {}
      end,
    }

    portforward = require("kubectl.actions.portforward")
  end)

  describe("extract_pod_ports (tested via portforward)", function()
    it("extracts ports from pod with single container", function()
      local spec_data = {
        spec = {
          containers = {
            {
              name = "nginx",
              ports = {
                { containerPort = 80, protocol = "TCP" },
              },
            },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      assert.are.equal(1, #captured_ports)
      assert.are.equal("nginx", captured_ports[1].name.value)
      assert.are.equal(80, captured_ports[1].port.value)
      assert.are.equal("TCP", captured_ports[1].protocol)
      assert.are.equal(mock_hl.symbols.pending, captured_ports[1].name.symbol)
      assert.are.equal(mock_hl.symbols.success, captured_ports[1].port.symbol)
    end)

    it("extracts ports from pod with multiple containers", function()
      local spec_data = {
        spec = {
          containers = {
            {
              name = "web",
              ports = {
                { containerPort = 80, name = "http", protocol = "TCP" },
                { containerPort = 443, name = "https", protocol = "TCP" },
              },
            },
            {
              name = "sidecar",
              ports = {
                { containerPort = 9090, protocol = "TCP" },
              },
            },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      assert.are.equal(3, #captured_ports)

      -- First container, first port
      assert.are.equal("web::(http)", captured_ports[1].name.value)
      assert.are.equal(80, captured_ports[1].port.value)

      -- First container, second port
      assert.are.equal("web::(https)", captured_ports[2].name.value)
      assert.are.equal(443, captured_ports[2].port.value)

      -- Second container
      assert.are.equal("sidecar", captured_ports[3].name.value)
      assert.are.equal(9090, captured_ports[3].port.value)
    end)

    it("handles pod with no ports", function()
      local spec_data = {
        spec = {
          containers = {
            { name = "app" },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      -- When no ports, should have fallback entry
      assert.are.equal(1, #captured_ports)
      assert.are.equal("", captured_ports[1].port.value)
      assert.are.equal("", captured_ports[1].name.value)
    end)

    it("handles pod with no containers", function()
      local spec_data = {
        spec = {},
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      -- When no containers, should have fallback entry
      assert.are.equal(1, #captured_ports)
      assert.are.equal("", captured_ports[1].port.value)
    end)

    it("handles port without name", function()
      local spec_data = {
        spec = {
          containers = {
            {
              name = "app",
              ports = {
                { containerPort = 8080, protocol = "TCP" },
              },
            },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      -- Container name without port name
      assert.are.equal("app", captured_ports[1].name.value)
    end)

    it("handles container without name", function()
      local spec_data = {
        spec = {
          containers = {
            {
              ports = {
                { containerPort = 8080, name = "http", protocol = "TCP" },
              },
            },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      -- No container name, should be nil
      assert.is_nil(captured_ports[1].name.value)
    end)
  end)

  describe("extract_service_ports (tested via portforward)", function()
    it("extracts ports from service with targetPort", function()
      local spec_data = {
        spec = {
          ports = {
            { name = "http", port = 80, targetPort = 8080, protocol = "TCP" },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("service", { k = "services" }, "test-svc", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      assert.are.equal(1, #captured_ports)
      assert.are.equal("http", captured_ports[1].name.value)
      assert.are.equal(8080, captured_ports[1].port.value) -- Should use targetPort
      assert.are.equal("TCP", captured_ports[1].protocol)
    end)

    it("falls back to port when targetPort is not specified", function()
      local spec_data = {
        spec = {
          ports = {
            { name = "http", port = 80, protocol = "TCP" },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("service", { k = "services" }, "test-svc", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      assert.are.equal(80, captured_ports[1].port.value) -- Falls back to port
    end)

    it("extracts multiple service ports", function()
      local spec_data = {
        spec = {
          ports = {
            { name = "http", port = 80, targetPort = 8080, protocol = "TCP" },
            { name = "https", port = 443, targetPort = 8443, protocol = "TCP" },
            { name = "metrics", port = 9090, protocol = "TCP" },
          },
        },
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("service", { k = "services" }, "test-svc", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      assert.are.equal(3, #captured_ports)

      assert.are.equal("http", captured_ports[1].name.value)
      assert.are.equal(8080, captured_ports[1].port.value)

      assert.are.equal("https", captured_ports[2].name.value)
      assert.are.equal(8443, captured_ports[2].port.value)

      assert.are.equal("metrics", captured_ports[3].name.value)
      assert.are.equal(9090, captured_ports[3].port.value) -- No targetPort, uses port
    end)

    it("handles service with no ports", function()
      local spec_data = {
        spec = {},
      }

      local mocks = setup_mocks(spec_data)
      portforward.portforward("service", { k = "services" }, "test-svc", "default")

      vim.wait(100, function()
        return mocks.get_captured_ports() ~= nil
      end)

      local captured_ports = mocks.get_captured_ports()
      assert.is_not_nil(captured_ports)
      -- When no ports, should have fallback entry
      assert.are.equal(1, #captured_ports)
      assert.are.equal("", captured_ports[1].port.value)
    end)
  end)

  describe("portforward", function()
    it("uses correct resource key for pod", function()
      local captured_resource
      local spec_data = { spec = { containers = {} } }

      setup_mocks(spec_data, {
        get_or_create = function(resource)
          captured_resource = resource
          return {
            data = nil,
            decodeJson = function() end,
            action_view = function() end,
          }
        end,
      })

      portforward.portforward("pod", { k = "pods" }, "test-pod", "default")

      vim.wait(100, function()
        return captured_resource ~= nil
      end)

      assert.are.equal("pod_pf", captured_resource)
    end)

    it("uses correct resource key for service", function()
      local captured_resource
      local spec_data = { spec = {} }

      setup_mocks(spec_data, {
        get_or_create = function(resource)
          captured_resource = resource
          return {
            data = nil,
            decodeJson = function() end,
            action_view = function() end,
          }
        end,
      })

      portforward.portforward("service", { k = "services" }, "test-svc", "default")

      vim.wait(100, function()
        return captured_resource ~= nil
      end)

      assert.are.equal("svc_pf", captured_resource)
    end)

    it("calls run_async with correct parameters", function()
      local captured_cmd, captured_args
      local spec_data = { spec = { containers = {} } }

      setup_mocks(spec_data, {
        run_async = function(cmd, args, callback)
          captured_cmd = cmd
          captured_args = args
          callback(spec_data)
        end,
      })

      local gvk = { k = "pods", v = "v1", g = "" }
      portforward.portforward("pod", gvk, "my-pod", "my-namespace")

      assert.are.equal("get_single_async", captured_cmd)
      assert.are.same(gvk, captured_args.gvk)
      assert.are.equal("my-pod", captured_args.name)
      assert.are.equal("my-namespace", captured_args.namespace)
    end)

    it("calls action_view with correct pf_data structure", function()
      local captured_def, captured_pf_data
      local spec_data = {
        spec = {
          containers = {
            {
              name = "app",
              ports = {
                { containerPort = 8080, protocol = "TCP" },
              },
            },
          },
        },
      }

      -- Use setup_mocks with custom action_view
      local mocks = setup_mocks(spec_data, {
        action_view = function(def, pf_data)
          captured_def = def
          captured_pf_data = pf_data
        end,
      })

      portforward.portforward("pod", { k = "pods" }, "test-pod", "test-ns")

      vim.wait(100, function()
        return captured_pf_data ~= nil
      end)

      assert.is_not_nil(captured_def, "action_view should have been called")
      assert.are.equal("pod_pf", captured_def.resource)
      assert.are.equal("k8s_action", captured_def.ft)
      assert.are.equal("test-ns", captured_def.ns)
      assert.is_true(captured_def.display:match("^PF: test%-pod") ~= nil)

      assert.is_not_nil(captured_pf_data)
      assert.are.equal(3, #captured_pf_data)

      -- Address field
      assert.are.equal("address:", captured_pf_data[1].text)
      assert.are.equal("localhost", captured_pf_data[1].value)
      assert.are.same({ "localhost", "0.0.0.0" }, captured_pf_data[1].options)
      assert.are.equal("positional", captured_pf_data[1].type)

      -- Local port field
      assert.are.equal("local:", captured_pf_data[2].text)
      assert.are.equal("8080", captured_pf_data[2].value)
      assert.are.equal("positional", captured_pf_data[2].type)

      -- Container port field
      assert.are.equal("container port:", captured_pf_data[3].text)
      assert.are.equal("8080", captured_pf_data[3].value)
      assert.are.equal(":", captured_pf_data[3].cmd)
      assert.are.equal("merge_above", captured_pf_data[3].type)
    end)

    it("calls portforward_start with correct args on action_view callback", function()
      local captured_pf_args
      local action_callback
      local spec_data = {
        spec = {
          containers = {
            {
              name = "app",
              ports = {
                { containerPort = 8080, protocol = "TCP" },
              },
            },
          },
        },
      }

      package.loaded["kubectl.client"] = {
        portforward_start = function(kind, name, ns, address, local_port, remote_port)
          captured_pf_args = {
            kind = kind,
            name = name,
            ns = ns,
            address = address,
            local_port = local_port,
            remote_port = remote_port,
          }
        end,
      }

      setup_mocks(spec_data, {
        action_view = function(_, _, callback)
          action_callback = callback
        end,
      })

      portforward.portforward("pod", { k = "pods" }, "test-pod", "test-ns")

      vim.wait(100, function()
        return action_callback ~= nil
      end)

      assert.is_not_nil(action_callback, "action_view should have been called with callback")

      -- Simulate user completing the action form
      action_callback({
        { value = "0.0.0.0" },
        { value = "9999" },
        { value = "8080" },
      })

      assert.is_not_nil(captured_pf_args)
      assert.are.equal("pods", captured_pf_args.kind)
      assert.are.equal("test-pod", captured_pf_args.name)
      assert.are.equal("test-ns", captured_pf_args.ns)
      assert.are.equal("0.0.0.0", captured_pf_args.address)
      assert.are.equal("9999", captured_pf_args.local_port)
      assert.are.equal("8080", captured_pf_args.remote_port)
    end)
  end)
end)
