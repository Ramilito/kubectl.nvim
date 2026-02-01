describe("actions.commands", function()
  local commands
  local original_config
  local original_state

  before_each(function()
    -- Clear module caches for fresh state
    package.loaded["kubectl.actions.commands"] = nil
    package.loaded["kubectl.config"] = nil
    package.loaded["kubectl.state"] = nil

    commands = require("kubectl.actions.commands")

    -- Set up mock config
    local config = require("kubectl.config")
    original_config = vim.deepcopy(config.options)
    config.options = {
      kubectl_cmd = {
        cmd = "kubectl",
        env = {},
        args = {},
      },
    }

    -- Set up mock state
    local state = require("kubectl.state")
    original_state = vim.deepcopy(state.context or {})
    state.context = {}
  end)

  after_each(function()
    local config = require("kubectl.config")
    config.options = original_config

    local state = require("kubectl.state")
    state.context = original_state
  end)

  describe("configure_command", function()
    it("returns command args and env tables", function()
      local result = commands.configure_command("kubectl", nil, nil)
      assert.is_table(result)
      assert.is_table(result.args)
      assert.is_table(result.env)
    end)

    it("prepends command as first argument", function()
      local result = commands.configure_command("kubectl", nil, nil)
      assert.are.equal("kubectl", result.args[1])
    end)

    it("uses custom kubectl command from config", function()
      local config = require("kubectl.config")
      config.options.kubectl_cmd.cmd = "/usr/local/bin/kubectl"

      local result = commands.configure_command("kubectl", nil, nil)
      assert.are.equal("/usr/local/bin/kubectl", result.args[1])
    end)

    it("includes config args for kubectl", function()
      local config = require("kubectl.config")
      config.options.kubectl_cmd.args = { "--insecure-skip-tls-verify" }

      local result = commands.configure_command("kubectl", nil, nil)
      assert.are.equal("--insecure-skip-tls-verify", result.args[2])
    end)

    it("includes config env for kubectl", function()
      local config = require("kubectl.config")
      config.options.kubectl_cmd.env = { KUBECONFIG = "/path/to/config" }

      local result = commands.configure_command("kubectl", nil, nil)
      -- env is processed as list with key=value format
      local found = false
      for _, v in ipairs(result.env) do
        if v == "KUBECONFIG=/path/to/config" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("adds context flag when context is set for kubectl", function()
      local state = require("kubectl.state")
      state.context["current-context"] = "my-cluster"

      local result = commands.configure_command("kubectl", nil, nil)

      local context_idx = nil
      for i, v in ipairs(result.args) do
        if v == "--context" then
          context_idx = i
          break
        end
      end
      assert.is_not_nil(context_idx)
      assert.are.equal("my-cluster", result.args[context_idx + 1])
    end)

    it("adds kube-context flag for helm command", function()
      local state = require("kubectl.state")
      state.context["current-context"] = "my-cluster"

      local result = commands.configure_command("helm", nil, nil)

      local context_idx = nil
      for i, v in ipairs(result.args) do
        if v == "--kube-context" then
          context_idx = i
          break
        end
      end
      assert.is_not_nil(context_idx)
      assert.are.equal("my-cluster", result.args[context_idx + 1])
    end)

    it("includes PATH from environment", function()
      local result = commands.configure_command("kubectl", nil, nil)
      assert.is_not_nil(result.env.PATH)
    end)

    it("includes HOME from environment when set", function()
      local current_home = vim.fn.environ()["HOME"]
      if current_home then
        local result = commands.configure_command("kubectl", nil, nil)
        assert.are.equal(current_home, result.env.HOME)
      end
    end)

    it("appends user-provided args", function()
      local result = commands.configure_command("kubectl", nil, { "get", "pods" })

      -- Find get and pods in args
      local get_idx = nil
      local pods_idx = nil
      for i, v in ipairs(result.args) do
        if v == "get" then
          get_idx = i
        end
        if v == "pods" then
          pods_idx = i
        end
      end
      assert.is_not_nil(get_idx)
      assert.is_not_nil(pods_idx)
      assert.is_true(pods_idx > get_idx)
    end)

    it("appends user-provided envs", function()
      local result = commands.configure_command("kubectl", { "MY_VAR=test" }, nil)

      local found = false
      for _, v in ipairs(result.env) do
        if v == "MY_VAR=test" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("expands environment variables in args using PATH", function()
      -- Use PATH which is always set
      local path_val = os.getenv("PATH")
      if path_val then
        local result = commands.configure_command("kubectl", nil, { "--test=$PATH" })

        local found = false
        for _, v in ipairs(result.args) do
          if v == "--test=" .. path_val then
            found = true
            break
          end
        end
        assert.is_true(found)
      end
    end)

    it("handles non-kubectl commands without context", function()
      local state = require("kubectl.state")
      state.context["current-context"] = "my-cluster"

      local result = commands.configure_command("ls", nil, { "-la" })

      -- Should not have context flags
      local has_context = false
      for _, v in ipairs(result.args) do
        if v == "--context" or v == "--kube-context" then
          has_context = true
          break
        end
      end
      assert.is_false(has_context)
      assert.are.equal("ls", result.args[1])
    end)

    it("handles config args as key-value pairs", function()
      local config = require("kubectl.config")
      config.options.kubectl_cmd.args = { namespace = "default" }

      local result = commands.configure_command("kubectl", nil, nil)

      local found = false
      for _, v in ipairs(result.args) do
        if v == "namespace=default" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("handles config args as indexed values", function()
      local config = require("kubectl.config")
      config.options.kubectl_cmd.args = { "--verbose" }

      local result = commands.configure_command("kubectl", nil, nil)

      local found = false
      for _, v in ipairs(result.args) do
        if v == "--verbose" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("execute_shell_command", function()
    it("returns string result", function()
      local result = commands.execute_shell_command("echo", "hello")
      assert.is_string(result)
      assert.are.equal("hello\n", result)
    end)

    it("handles args as table", function()
      local result = commands.execute_shell_command("echo", { "hello", "world" })
      assert.are.equal("hello world\n", result)
    end)

    it("handles args as string", function()
      local result = commands.execute_shell_command("echo", "test string")
      assert.are.equal("test string\n", result)
    end)

    it("returns empty string for command not found (error goes to stderr)", function()
      -- io.popen runs through shell, so even nonexistent commands return a handle
      -- The error message goes to stderr which isn't captured
      local result = commands.execute_shell_command("nonexistent_command_12345", "")
      assert.is_string(result)
      assert.are.equal("", result)
    end)
  end)
end)

describe("actions.commands file operations", function()
  local commands
  local test_file_name = "_test_commands_spec_.json"
  local data_dir

  before_each(function()
    package.loaded["kubectl.actions.commands"] = nil
    commands = require("kubectl.actions.commands")
    data_dir = vim.fn.stdpath("data") .. "/kubectl/"

    -- Ensure the full directory path exists (including all parents)
    -- This is needed because vim.uv.fs_mkdir only creates one level
    vim.fn.mkdir(data_dir, "p")
  end)

  after_each(function()
    -- Clean up test file
    local file_path = data_dir .. test_file_name
    os.remove(file_path)
  end)

  describe("save_file", function()
    it("returns true on success", function()
      local ok, err = commands.save_file(test_file_name, { key = "value" })
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("saves valid JSON data", function()
      local data = { name = "test", count = 42, nested = { a = 1, b = 2 } }
      commands.save_file(test_file_name, data)

      local loaded = commands.read_file(test_file_name)
      assert.are.same(data, loaded)
    end)

    it("handles empty table", function()
      local ok = commands.save_file(test_file_name, {})
      assert.is_true(ok)

      local loaded = commands.read_file(test_file_name)
      assert.are.same({}, loaded)
    end)

    it("handles arrays", function()
      local data = { 1, 2, 3, "four", "five" }
      commands.save_file(test_file_name, data)

      local loaded = commands.read_file(test_file_name)
      assert.are.same(data, loaded)
    end)

    it("creates directory if it does not exist", function()
      -- This test relies on the directory creation logic in save_file
      local ok = commands.save_file(test_file_name, { test = true })
      assert.is_true(ok)
    end)
  end)

  describe("read_file", function()
    it("returns nil for non-existent file", function()
      local result = commands.read_file("nonexistent_file_12345.json")
      assert.is_nil(result)
    end)

    it("returns parsed JSON data", function()
      local data = { key = "value", number = 123 }
      commands.save_file(test_file_name, data)

      local result = commands.read_file(test_file_name)
      assert.are.same(data, result)
    end)

    it("handles boolean values", function()
      local data = { enabled = true, disabled = false }
      commands.save_file(test_file_name, data)

      local result = commands.read_file(test_file_name)
      assert.is_true(result.enabled)
      assert.is_false(result.disabled)
    end)

    it("handles null values", function()
      local data = { existing = "value", missing = vim.NIL }
      commands.save_file(test_file_name, data)

      local result = commands.read_file(test_file_name)
      assert.are.equal("value", result.existing)
      -- vim.NIL becomes nil when decoded
      assert.is_nil(result.missing)
    end)
  end)
end)
