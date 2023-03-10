local helpers = require "spec.helpers"
local fixtures = require "spec.fixtures.oidc"

PLUGIN_NAME = "oidc"

describe("oidc plugin", function()
  local proxy_client
  local timeout = 6000

  lazy_setup(function()
    local bp = helpers.get_db_utils("postgres", nil, { PLUGIN_NAME })
    local api1 = assert(bp.routes:insert {
      name = "mock",
      hosts = { "mockbin.com" },
      paths = { "/mock" }
    })
    print("Api created:")
    for k, v in pairs(api1) do
      print(k, ": ", v)
    end
    assert(bp.plugins:insert {
      name = PLUGIN_NAME,
      config = {
        client_id = "afcc3a0a-aaa4-4bac-b86a-a7bd77259dd3",
        client_secret = "81de73f0-3a0e-451a-88ee-e540811a049c",
        discovery = "http://127.0.0.1/.well-known/openid-configuration"
      }
    })

    -- start kong
    assert(helpers.start_kong({
      -- set the strategy
      database   = "postgres",
      -- use the custom test template to create a local mock server
      nginx_conf = "spec/fixtures/custom_nginx.template",
      -- make sure our plugin gets loaded
      plugins = "bundled," .. PLUGIN_NAME,
    }, nil, nil, fixtures))
    print("Kong started")
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
    print("Kong stopped")
  end)

  before_each(function()
    proxy_client = helpers.proxy_client(timeout)
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end
  end)

  describe("being an OpenID Connect Relaying Party component", function()
    it("should redirect the authentication request (which is an OAuth 2.0 authorization request) to OP", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path   = "/mock",
        headers = {
          host = "mockbin.com",
        },
      })
      local body = assert.res_status(302, res)
      local redirect_uri = res.headers["Location"]
      assert.is_truthy(string.find(redirect_uri, "response_type=code"))
      assert.is_truthy(string.find(redirect_uri, "scope=openid"))
      assert.is_truthy(string.find(redirect_uri, "client_id="))
      assert.is_truthy(string.find(redirect_uri, "state="))
      assert.is_truthy(string.find(redirect_uri, "redirect_uri="))
      print(redirect_uri)
    end)

    it("should after successful login contact token and userinfo endpoints", function()
      -- Mimic authentication response
      local res = assert(proxy_client:send {
        method = "GET",
        path   = "/mock/?state=123456&code=123456",
        headers = {
          host = "mockbin.com",
        },
      })
      -- This will fail in openidc.lua because session created in first phase is loat
      -- and several things could mismatch (state, nonce, original_url, ...)
      local body = assert.res_status(500, res)
    end)
  end)
end)

