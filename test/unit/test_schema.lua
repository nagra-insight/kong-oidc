local lu = require("luaunit")
local Schema = require "kong.db.schema"

TestSchema = {}

function TestSchema:setUp()
    local plugin_schema = require("kong.plugins.oidc.schema")
    self.schema = assert(Schema.new(plugin_schema))
end

function TestSchema:validate(config)
    local entity = {
        config = config
    }
    return self.schema:validate(entity)
end

-- Test: client_id and client_secret are required when bearer_jwt_auth_enable is not set
function TestSchema:test_requires_client_credentials_when_bearer_jwt_auth_not_set()
    local config = {
        discovery = "https://example.com/.well-known/openid-configuration"
    }
    local ok, err = self:validate(config)
    lu.assertFalse(ok)
    lu.assertNotNil(err)
    local err_str = tostring(err)
    lu.assertTrue(
        err_str:match("client_id is required") ~= nil or
        err_str:match("client_secret is required") ~= nil
    )
end

-- Test: client_id and client_secret are required when bearer_jwt_auth_enable is 'no'
function TestSchema:test_requires_client_credentials_when_bearer_jwt_auth_is_no()
    local config = {
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "no"
    }
    local ok, err = self:validate(config)
    lu.assertFalse(ok)
    lu.assertNotNil(err)
end

-- Test: rejects config without client_id when bearer_jwt_auth_enable is 'no'
function TestSchema:test_rejects_missing_client_id_when_bearer_jwt_auth_is_no()
    local config = {
        client_secret = "test-client-secret",
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "no"
    }
    local ok, err = self:validate(config)
    lu.assertFalse(ok)
    lu.assertNotNil(err)
    lu.assertStrContains(tostring(err), "client_id is required when bearer_jwt_auth_enable is not 'yes'")
end

-- Test: rejects config without client_secret when bearer_jwt_auth_enable is 'no'
function TestSchema:test_rejects_missing_client_secret_when_bearer_jwt_auth_is_no()
    local config = {
        client_id = "test-client-id",
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "no"
    }
    local ok, err = self:validate(config)
    lu.assertFalse(ok)
    lu.assertNotNil(err)
    lu.assertStrContains(tostring(err), "client_secret is required when bearer_jwt_auth_enable is not 'yes'")
end

-- Test: accepts config with both credentials when bearer_jwt_auth_enable is not set
function TestSchema:test_accepts_config_with_credentials_when_bearer_jwt_auth_not_set()
    local config = {
        client_id = "test-client-id",
        client_secret = "test-client-secret",
        discovery = "https://example.com/.well-known/openid-configuration"
    }
    local ok, err = self:validate(config)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

-- Test: accepts config with both credentials when bearer_jwt_auth_enable is 'no'
function TestSchema:test_accepts_config_with_credentials_when_bearer_jwt_auth_is_no()
    local config = {
        client_id = "test-client-id",
        client_secret = "test-client-secret",
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "no"
    }
    local ok, err = self:validate(config)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

-- Test: accepts config without client_id and client_secret when bearer_jwt_auth_enable is 'yes'
function TestSchema:test_accepts_config_without_credentials_when_bearer_jwt_auth_is_yes()
    local config = {
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "yes"
    }
    local ok, err = self:validate(config)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

-- Test: accepts config with credentials when bearer_jwt_auth_enable is 'yes' (optional but allowed)
function TestSchema:test_accepts_config_with_credentials_when_bearer_jwt_auth_is_yes()
    local config = {
        client_id = "test-client-id",
        client_secret = "test-client-secret",
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "yes"
    }
    local ok, err = self:validate(config)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

-- Test: accepts config without client_id when bearer_jwt_auth_enable is 'yes'
function TestSchema:test_accepts_config_without_client_id_when_bearer_jwt_auth_is_yes()
    local config = {
        client_secret = "test-client-secret",
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "yes"
    }
    local ok, err = self:validate(config)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

-- Test: accepts config without client_secret when bearer_jwt_auth_enable is 'yes'
function TestSchema:test_accepts_config_without_client_secret_when_bearer_jwt_auth_is_yes()
    local config = {
        client_id = "test-client-id",
        discovery = "https://example.com/.well-known/openid-configuration",
        bearer_jwt_auth_enable = "yes"
    }
    local ok, err = self:validate(config)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

-- Test: discovery field is always required
function TestSchema:test_requires_discovery_field()
    local config = {
        client_id = "test-client-id",
        client_secret = "test-client-secret"
    }
    local ok, err = self:validate(config)
    lu.assertFalse(ok)
    lu.assertNotNil(err)
    lu.assertStrContains(tostring(err), "discovery")
end

lu.LuaUnit.run()
