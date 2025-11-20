local lu = require("luaunit")
TestHandler = require("test.unit.mockable_case"):extend()


function TestHandler:setUp()
    TestHandler.super:setUp()

    package.loaded["resty.openidc"] = nil
    self.module_resty = { openidc = {} }
    package.preload["resty.openidc"] = function()
        return self.module_resty.openidc
    end

    self.handler = require("kong.plugins.oidc.handler")
end

function TestHandler:tearDown()
    TestHandler.super:tearDown()
end

function TestHandler:test_bearer_jwt_auth_success()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    self.module_resty.openidc.bearer_jwt_verify = function(opts)
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            groups = { "users" }
        }
        return token, nil, "xxx"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        groups_claim = "groups",
        userinfo_header_name = "x-userinfo"
    })
    lu.assertEquals(ngx.ctx.authenticated_credential.id, "sub111")
    lu.assertEquals(kong.ctx.shared.authenticated_groups, { "users" })
end

function TestHandler:test_bearer_jwt_auth_fail()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    local called_authenticate
    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    self.module_resty.openidc.bearer_jwt_verify = function(opts)
        return nil, "JWT expired"
    end

    self.module_resty.openidc.authenticate = function(opts)
        called_authenticate = true
        return nil, "error"
    end
    self.handler:access({ bearer_jwt_auth_enable = "yes", client_id = "aud222" })
    lu.assertTrue(called_authenticate)
end

function TestHandler:test_bearer_jwt_auth_with_scope_validation_success()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    local claim_spec_received = nil
    self.module_resty.openidc.bearer_jwt_verify = function(opts, claim_spec)
        claim_spec_received = claim_spec
        -- Simulate JWT token with required scope
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            scope = "read write admin",
            groups = { "users" }
        }

        -- Execute the scope validator if present
        if claim_spec and claim_spec.scope then
            local scope_valid = claim_spec.scope(token.scope)
            if not scope_valid then
                return nil, "scope validation failed"
            end
        end

        return token, nil, "xxx"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        bearer_jwt_auth_required_scopes = { "admin" },
        groups_claim = "groups",
        userinfo_header_name = "x-userinfo"
    })

    lu.assertNotNil(claim_spec_received)
    lu.assertNotNil(claim_spec_received.scope)
    lu.assertEquals(ngx.ctx.authenticated_credential.id, "sub111")
    lu.assertEquals(kong.ctx.shared.authenticated_groups, { "users" })
end

function TestHandler:test_bearer_jwt_auth_with_scope_validation_failure()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    local claim_spec_received = nil
    self.module_resty.openidc.bearer_jwt_verify = function(opts, claim_spec)
        claim_spec_received = claim_spec
        -- Simulate JWT token without required scope
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            scope = "read write", -- missing "admin" scope
            groups = { "users" }
        }

        -- Execute the scope validator if present
        if claim_spec and claim_spec.scope then
            local scope_valid = claim_spec.scope(token.scope)
            if not scope_valid then
                return nil, "scope validation failed"
            end
        end

        return token, nil, "xxx"
    end

    local called_authenticate = false
    self.module_resty.openidc.authenticate = function(opts)
        called_authenticate = true
        return nil, "error"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        bearer_jwt_auth_required_scopes = { "admin" },
        groups_claim = "groups"
    })

    lu.assertNotNil(claim_spec_received)
    lu.assertNotNil(claim_spec_received.scope)
    lu.assertTrue(called_authenticate)
end

function TestHandler:test_bearer_jwt_auth_with_scope_validation_no_scope_claim()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    local claim_spec_received = nil
    self.module_resty.openidc.bearer_jwt_verify = function(opts, claim_spec)
        claim_spec_received = claim_spec
        -- Simulate JWT token without scope claim at all
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            groups = { "users" }
            -- no scope claim
        }

        -- Execute the scope validator if present
        if claim_spec and claim_spec.scope then
            local scope_valid = claim_spec.scope(token.scope)
            if not scope_valid then
                return nil, "scope validation failed"
            end
        end

        return token, nil, "xxx"
    end

    local called_authenticate = false
    self.module_resty.openidc.authenticate = function(opts)
        called_authenticate = true
        return nil, "error"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        bearer_jwt_auth_required_scopes = { "admin" },
        groups_claim = "groups"
    })

    lu.assertNotNil(claim_spec_received)
    lu.assertNotNil(claim_spec_received.scope)
    -- Should fail when no scope claim in token (restrictive behavior)
    lu.assertTrue(called_authenticate)
end

function TestHandler:test_bearer_jwt_auth_without_scope_validation()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    local claim_spec_received = nil
    self.module_resty.openidc.bearer_jwt_verify = function(opts, claim_spec)
        claim_spec_received = claim_spec
        -- Simulate JWT token without the required scope
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            scope = "read", -- doesn't have "admin" but validation is disabled
            groups = { "users" }
        }

        -- Execute the scope validator if present
        if claim_spec and claim_spec.scope then
            local scope_valid = claim_spec.scope(token.scope)
            if not scope_valid then
                return nil, "scope validation failed"
            end
        end

        return token, nil, "xxx"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        -- no bearer_jwt_auth_required_scopes means scope validation is disabled
        groups_claim = "groups",
        userinfo_header_name = "x-userinfo"
    })

    lu.assertNotNil(claim_spec_received)
    lu.assertNotNil(claim_spec_received.scope)
    -- Should succeed even without the required scope because validation is disabled
    lu.assertEquals(ngx.ctx.authenticated_credential.id, "sub111")
    lu.assertEquals(kong.ctx.shared.authenticated_groups, { "users" })
end

function TestHandler:test_bearer_jwt_auth_with_multiple_required_scopes_success()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    local claim_spec_received = nil
    self.module_resty.openidc.bearer_jwt_verify = function(opts, claim_spec)
        claim_spec_received = claim_spec
        -- Simulate JWT token with one of the required scopes
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            scope = "read write", -- has "write" which is in required list
            groups = { "users" }
        }

        -- Execute the scope validator if present
        if claim_spec and claim_spec.scope then
            local scope_valid = claim_spec.scope(token.scope)
            if not scope_valid then
                return nil, "scope validation failed"
            end
        end

        return token, nil, "xxx"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        bearer_jwt_auth_required_scopes = { "admin", "write", "execute" }, -- OR logic
        groups_claim = "groups",
        userinfo_header_name = "x-userinfo"
    })

    lu.assertNotNil(claim_spec_received)
    lu.assertNotNil(claim_spec_received.scope)
    -- Should succeed because token has "write" which is one of the required scopes
    lu.assertEquals(ngx.ctx.authenticated_credential.id, "sub111")
    lu.assertEquals(kong.ctx.shared.authenticated_groups, { "users" })
end

function TestHandler:test_bearer_jwt_auth_with_multiple_required_scopes_failure()
    ngx.req.get_headers = function() return { Authorization = "Bearer xxx" } end
    ngx.encode_base64 = function(x) return "eyJzdWIiOiJzdWIifQ==" end

    self.module_resty.openidc.get_discovery_doc = function(opts)
        return { issuer = "https://oidc" }
    end

    local claim_spec_received = nil
    self.module_resty.openidc.bearer_jwt_verify = function(opts, claim_spec)
        claim_spec_received = claim_spec
        -- Simulate JWT token without any of the required scopes
        token = {
            iss = "https://oidc",
            sub = "sub111",
            aud = "aud222",
            scope = "read profile", -- doesn't have admin, write, or execute
            groups = { "users" }
        }

        -- Execute the scope validator if present
        if claim_spec and claim_spec.scope then
            local scope_valid = claim_spec.scope(token.scope)
            if not scope_valid then
                return nil, "scope validation failed"
            end
        end

        return token, nil, "xxx"
    end

    local called_authenticate = false
    self.module_resty.openidc.authenticate = function(opts)
        called_authenticate = true
        return nil, "error"
    end

    self.handler:access({
        bearer_jwt_auth_enable = "yes",
        client_id = "aud222",
        bearer_jwt_auth_required_scopes = { "admin", "write", "execute" },
        groups_claim = "groups"
    })

    lu.assertNotNil(claim_spec_received)
    lu.assertNotNil(claim_spec_received.scope)
    -- Should fail because token doesn't have any of the required scopes
    lu.assertTrue(called_authenticate)
end

lu.run()
