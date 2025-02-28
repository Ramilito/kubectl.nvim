--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
  haystacks_by_provider_cache = {},
}

function client.set_implementation()
  client.implementation = require("kubectl.client.rust")
end

function client.test()
  client.implementation.test("from lua called")
end

return client
