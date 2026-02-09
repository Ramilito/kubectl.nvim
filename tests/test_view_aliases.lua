-- Feature Tier: Tests view alias resolution
-- Guards the user-facing feature of resolving user-typed aliases to canonical resource names

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local viewsTable = require("kubectl.utils.viewsTable")

local T = new_set()

-- Resolve an alias to its canonical resource name
local function resolve_alias(alias)
  for resource, aliases in pairs(viewsTable) do
    for _, a in ipairs(aliases) do
      if a == alias then
        return resource
      end
    end
  end
  return nil
end

T["alias resolution"] = new_set()

T["alias resolution"]["resolves canonical name to itself"] = function()
  expect.equality(resolve_alias("pods"), "pods")
end

T["alias resolution"]["resolves short alias to canonical name"] = function()
  expect.equality(resolve_alias("po"), "pods")
end

T["alias resolution"]["resolves deploy to deployments"] = function()
  expect.equality(resolve_alias("deploy"), "deployments")
end

T["alias resolution"]["resolves qualified name to canonical"] = function()
  expect.equality(resolve_alias("deployments.apps"), "deployments")
end

T["alias resolution"]["resolves svc to services"] = function()
  expect.equality(resolve_alias("svc"), "services")
end

T["alias resolution"]["resolves sts to statefulsets"] = function()
  expect.equality(resolve_alias("sts"), "statefulsets")
end

T["alias resolution"]["resolves ds to daemonsets"] = function()
  expect.equality(resolve_alias("ds"), "daemonsets")
end

T["alias resolution"]["resolves cj to cronjobs"] = function()
  expect.equality(resolve_alias("cj"), "cronjobs")
end

T["alias resolution"]["resolves hpa to horizontalpodautoscalers"] = function()
  expect.equality(resolve_alias("hpa"), "horizontalpodautoscalers")
end

T["alias resolution"]["resolves pv to persistentvolumes"] = function()
  expect.equality(resolve_alias("pv"), "persistentvolumes")
end

T["alias resolution"]["resolves pvc to persistentvolumeclaims"] = function()
  expect.equality(resolve_alias("pvc"), "persistentvolumeclaims")
end

T["alias resolution"]["resolves cm to configmaps"] = function()
  expect.equality(resolve_alias("cm"), "configmaps")
end

T["alias resolution"]["resolves ing to ingresses"] = function()
  expect.equality(resolve_alias("ing"), "ingresses")
end

T["alias resolution"]["resolves sa to serviceaccounts"] = function()
  expect.equality(resolve_alias("sa"), "serviceaccounts")
end

T["alias resolution"]["resolves no to nodes"] = function()
  expect.equality(resolve_alias("no"), "nodes")
end

T["alias resolution"]["returns nil for unknown alias"] = function()
  expect.equality(resolve_alias("unknown"), nil)
end

T["alias resolution"]["returns nil for empty string"] = function()
  expect.equality(resolve_alias(""), nil)
end

return T
