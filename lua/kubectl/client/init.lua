--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
  haystacks_by_provider_cache = {},
}

function client.set_implementation()
  client.implementation = require("kubectl.client.rust")
	client.implementation.init_client()
end

function client.get_resource(...)
  return client.implementation.get_resource(...)
end

return client
