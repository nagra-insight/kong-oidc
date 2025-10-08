local PLUGIN_NAME = "oidc"
local Schema = require "kong.db.schema"

describe("Plugin: " .. PLUGIN_NAME .. " (schema)", function()
    local schema
    local validate

    local function find_error_message(err, pattern)
        if type(err) == "string" then
            return err:find(pattern, 1, true) ~= nil
        elseif type(err) == "table" then
            for k, v in pairs(err) do
                if find_error_message(v, pattern) then
                    return true
                end
            end
        end
        return false
    end

    lazy_setup(function()
        local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")
        schema = assert(Schema.new(plugin_schema))
        validate = function(config)
            local entity = {
                config = config,
                protocols = { "http", "https" }
            }
            return schema:validate(entity)
        end
    end)

    describe("client_id and client_secret validation", function()
        it("accepts config with client_id and client_secret when bearer_jwt_auth_enable is not set", function()
            local config = {
                client_id = "test-client-id",
                client_secret = "test-client-secret",
                discovery = "https://example.com/.well-known/openid-configuration"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)

        it("accepts config with client_id and client_secret when bearer_jwt_auth_enable is 'no'", function()
            local config = {
                client_id = "test-client-id",
                client_secret = "test-client-secret",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "no"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)

        it("rejects config without client_id when bearer_jwt_auth_enable is not 'yes'", function()
            local config = {
                client_secret = "test-client-secret",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "no"
            }
            local ok, err = validate(config)
            assert.is_falsy(ok)
            assert.is_not_nil(err)
            assert.is_true(find_error_message(err, "client_id is required when bearer_jwt_auth_enable is not 'yes'"))
        end)

        it("rejects config without client_secret when bearer_jwt_auth_enable is not 'yes'", function()
            local config = {
                client_id = "test-client-id",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "no"
            }
            local ok, err = validate(config)
            assert.is_falsy(ok)
            assert.is_not_nil(err)
            assert.is_true(find_error_message(err, "client_secret is required when bearer_jwt_auth_enable is not 'yes'"))
        end)

        it("rejects config without both client_id and client_secret when bearer_jwt_auth_enable is not set", function()
            local config = {
                discovery = "https://example.com/.well-known/openid-configuration"
            }
            local ok, err = validate(config)
            assert.is_falsy(ok)
            assert.is_not_nil(err)
            -- Should fail on client_id or client_secret validation
            assert.is_true(
                find_error_message(err, "client_id is required") or
                find_error_message(err, "client_secret is required")
            )
        end)

        it("accepts config without client_id and client_secret when bearer_jwt_auth_enable is 'yes'", function()
            local config = {
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "yes"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)

        it("accepts config with client_id and client_secret when bearer_jwt_auth_enable is 'yes'", function()
            local config = {
                client_id = "test-client-id",
                client_secret = "test-client-secret",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "yes"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)

        it("accepts config without client_id when bearer_jwt_auth_enable is 'yes'", function()
            local config = {
                client_secret = "test-client-secret",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "yes"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)

        it("accepts config without client_secret when bearer_jwt_auth_enable is 'yes'", function()
            local config = {
                client_id = "test-client-id",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_jwt_auth_enable = "yes"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)
    end)

    describe("other required fields", function()
        it("requires discovery field", function()
            local config = {
                client_id = "test-client-id",
                client_secret = "test-client-secret"
            }
            local ok, err = validate(config)
            assert.is_falsy(ok)
            assert.is_not_nil(err)
            assert.is_true(
                find_error_message(err, "discovery") or
                find_error_message(err, "required field missing")
            )
        end)

        it("accepts minimal valid configuration", function()
            local config = {
                client_id = "test-client-id",
                client_secret = "test-client-secret",
                discovery = "https://example.com/.well-known/openid-configuration"
            }
            local ok, err = validate(config)
            assert.is_truthy(ok)
            assert.is_nil(err)
        end)
    end)
end)
