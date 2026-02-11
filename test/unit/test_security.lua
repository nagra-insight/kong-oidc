-- Security-focused unit tests for kong-oidc plugin
-- Tests cover: filter bypass prevention, header sanitization,
-- session config validation, and credential mutation prevention

-- Set up ngx globals BEFORE requiring modules that depend on kong.constants
package.path = package.path .. ";test/lib/?.lua;;"

_G.ngx = {
    DEBUG = 7,
    INFO = 6,
    NOTICE = 5,
    WARN = 4,
    ERR = 3,
    CRIT = 2,
    ALERT = 1,
    EMERG = 0,
    var = { uri = "" },
    unescape_uri = function(s)
        return (s:gsub("%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end))
    end
}

_G.kong = {
    log = { err = function() end },
    service = {
        request = {
            clear_header = function() end,
            set_header = function() end
        }
    }
}

local lu = require("luaunit")
local filter = require("kong.plugins.oidc.filter")
local utils = require("kong.plugins.oidc.utils")

TestSecurity = require("test.unit.base_case"):extend()

function TestSecurity:setUp()
    TestSecurity.super:setUp()
    _G.ngx.var = { uri = "" }
end

function TestSecurity:tearDown()
    TestSecurity.super:tearDown()
end

--------------------------------------------------------------------------------
-- Filter Bypass Prevention Tests
-- Verifies that URL normalization prevents bypass of regex-based filters
--------------------------------------------------------------------------------

-- Config uses regex patterns (backward compatible)
local filter_config = { filters = { "^/logout", "^/health", "^/public" } }

function TestSecurity:testFilterMatchesNormalPath()
    ngx.var.uri = "/logout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterMatchesPathWithSubpath()
    ngx.var.uri = "/logout/callback"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksUrlEncodedBypass()
    -- %6C = 'l', so /%6Cogout = /logout after decoding
    ngx.var.uri = "/%6Cogout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksFullUrlEncodedPath()
    -- %2F = '/', %6C = 'l', %6F = 'o', %67 = 'g', %75 = 'u', %74 = 't'
    ngx.var.uri = "/%6C%6F%67%6F%75%74"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksCaseVariationUppercase()
    -- Normalization lowercases the path before matching
    ngx.var.uri = "/LOGOUT"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksCaseVariationMixed()
    ngx.var.uri = "/LoGoUt"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksPathTraversalSimple()
    -- /foo/../logout normalizes to /logout
    ngx.var.uri = "/foo/../logout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksPathTraversalDeep()
    ngx.var.uri = "/a/b/c/../../../logout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksDoubleSlash()
    -- //logout normalizes to /logout
    ngx.var.uri = "//logout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksDotSegments()
    -- /./logout normalizes to /logout
    ngx.var.uri = "/./logout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterBlocksLeadingTraversal()
    -- /../../../logout normalizes to /logout
    ngx.var.uri = "/../../../logout"
    lu.assertFalse(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterAllowsUnmatchedPaths()
    ngx.var.uri = "/api/users"
    lu.assertTrue(filter.shouldProcessRequest(filter_config))
end

function TestSecurity:testFilterAllowsPartialMatch()
    -- /logoutpage should not match ^/logout$ but will match ^/logout
    -- This tests that regex still works as expected
    local strict_config = { filters = { "^/logout$" } }
    ngx.var.uri = "/logoutpage"
    lu.assertTrue(filter.shouldProcessRequest(strict_config))
end

--------------------------------------------------------------------------------
-- Header Sanitization Tests
-- Verifies that header values are sanitized to prevent HTTP response splitting
--------------------------------------------------------------------------------

function TestSecurity:testSanitizeRemovesCR()
    local malicious = "value\rinjected"
    local sanitized = utils.sanitize_header_value(malicious)
    lu.assertNil(sanitized:find("\r"))
end

function TestSecurity:testSanitizeRemovesLF()
    local malicious = "value\ninjected"
    local sanitized = utils.sanitize_header_value(malicious)
    lu.assertNil(sanitized:find("\n"))
end

function TestSecurity:testSanitizeRemovesCRLF()
    local malicious = "value\r\nSet-Cookie: evil=true"
    local sanitized = utils.sanitize_header_value(malicious)
    lu.assertNil(sanitized:find("\r"))
    lu.assertNil(sanitized:find("\n"))
    lu.assertEquals(sanitized, "valueSet-Cookie: evil=true")
end

function TestSecurity:testSanitizeRemovesNullByte()
    local malicious = "value" .. string.char(0) .. "injected"
    local sanitized = utils.sanitize_header_value(malicious)
    lu.assertNil(sanitized:find("%z"))
    lu.assertEquals(sanitized, "valueinjected")
end

function TestSecurity:testSanitizeEscapesQuotes()
    local malicious = 'value",error="injected'
    local sanitized = utils.sanitize_header_value(malicious)
    lu.assertEquals(sanitized, 'value\\",error=\\"injected')
end

function TestSecurity:testSanitizeHandlesNil()
    lu.assertEquals(utils.sanitize_header_value(nil), "")
end

function TestSecurity:testSanitizeHandlesNumber()
    lu.assertEquals(utils.sanitize_header_value(123), "123")
end

function TestSecurity:testSanitizeHandlesCleanString()
    lu.assertEquals(utils.sanitize_header_value("clean value"), "clean value")
end

--------------------------------------------------------------------------------
-- Session Config Fail-Closed Tests
-- Verifies that invalid session config causes error instead of silent fallback
--------------------------------------------------------------------------------

function TestSecurity:testSessionOptsReturnsErrorOnInvalidJson()
    local config = { session = "not valid json" }
    local opts, err = utils.get_session_opts(config)
    lu.assertNil(opts)
    lu.assertNotNil(err)
    lu.assertStrContains(err, "Invalid session configuration")
end

function TestSecurity:testSessionOptsReturnsErrorOnJsonArray()
    local config = { session = '["array", "not", "object"]' }
    local opts, err = utils.get_session_opts(config)
    lu.assertNil(opts)
    lu.assertNotNil(err)
    lu.assertStrContains(err, "must be a JSON object")
end

function TestSecurity:testSessionOptsReturnsEmptyTableWhenNil()
    local config = { session = nil }
    local opts, err = utils.get_session_opts(config)
    lu.assertNotNil(opts)
    lu.assertNil(err)
end

function TestSecurity:testSessionOptsReturnsEmptyTableWhenEmpty()
    local config = { session = "" }
    local opts, err = utils.get_session_opts(config)
    lu.assertNotNil(opts)
    lu.assertNil(err)
end

function TestSecurity:testSessionOptsReturnsTableOnValidJson()
    local config = { session = '{"cookie_secure": true, "cookie_name": "session"}' }
    local opts, err = utils.get_session_opts(config)
    lu.assertNotNil(opts)
    lu.assertNil(err)
    lu.assertEquals(opts.cookie_secure, true)
    lu.assertEquals(opts.cookie_name, "session")
end

--------------------------------------------------------------------------------
-- setCredentials Mutation Tests
-- Verifies that original user object is not mutated
--------------------------------------------------------------------------------

function TestSecurity:testSetCredentialsDoesNotMutateOriginal()
    local captured_credential = nil
    _G.kong.client = {
        authenticate = function(consumer, credential)
            captured_credential = credential
        end
    }

    local original = {
        sub = "user-123",
        preferred_username = "testuser",
        email = "test@example.com",
        groups = { "admin", "users" }
    }

    local original_groups = original.groups

    utils.setCredentials(original)

    -- Original should NOT have id and username fields added
    lu.assertNil(original.id)
    lu.assertNil(original.username)

    -- Original fields should be unchanged
    lu.assertEquals(original.sub, "user-123")
    lu.assertEquals(original.preferred_username, "testuser")
    lu.assertEquals(original.email, "test@example.com")
    lu.assertEquals(original.groups, original_groups)

    -- Credential passed to authenticate should have the mapped fields
    lu.assertNotNil(captured_credential)
    lu.assertEquals(captured_credential.id, "user-123")
    lu.assertEquals(captured_credential.username, "testuser")
    lu.assertEquals(captured_credential.sub, "user-123")
    lu.assertEquals(captured_credential.email, "test@example.com")
end

function TestSecurity:testSetCredentialsHandlesMissingFields()
    _G.kong.client = {
        authenticate = function() end
    }

    local original = {
        sub = "user-456"
        -- preferred_username is missing
    }

    -- Should not crash
    utils.setCredentials(original)

    -- Original should be unchanged
    lu.assertEquals(original.sub, "user-456")
    lu.assertNil(original.id)
end

lu.run()
