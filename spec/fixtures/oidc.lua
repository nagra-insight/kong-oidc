local helpers = require "spec.helpers"

local fixtures = {
  http_mock = {
    lambda_plugin = [[

      server {
          server_name kong;
          listen 80;

          location ~ ".well-known/openid-configuration" {
              content_by_lua_block {
                ngx.sleep(.2) -- mock some network latency

                ngx.status = 200
                ngx.say('{'..
                    '"issuer": "http://127.0.0.1",'..
                    '"authorization_endpoint": "http://127.0.0.1/protocol/openid-connect/auth",'..
                    '"token_endpoint": "http://127.0.0.1/protocol/openid-connect/token",'..
                    '"introspection_endpoint": "http://127.0.0.1/protocol/openid-connect/token/introspect",'..
                    '"userinfo_endpoint": "http://127.0.0.1/protocol/openid-connect/userinfo",'..
                    '"jwks_uri": "http://127.0.0.1/protocol/openid-connect/certs"'..
                '}')
                ngx.exit(0)
              }
          }
      }

    ]]
  },
}

return fixtures
