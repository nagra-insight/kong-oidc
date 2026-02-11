# Security Review - Kong OIDC Plugin

This document summarizes the security review conducted on the Kong OIDC plugin, including identified vulnerabilities, attack patterns, and implemented mitigations.

## Overview

The Kong OIDC plugin provides OpenID Connect authentication for Kong API Gateway. This security review focused on identifying vulnerabilities that could compromise authentication, enable unauthorized access, or leak sensitive information.

**Review Scope:** `kong-oidc/kong/plugins/oidc/`

---

## Implemented Fixes

### 1. SSL/TLS Verification Enabled by Default

**Severity:** Critical

**Attack Pattern:**
An attacker performs a Man-in-the-Middle (MITM) attack between Kong and the OIDC provider. By intercepting the discovery document request, the attacker returns modified endpoints pointing to malicious servers. This allows capture of client credentials, token interception, and complete authentication bypass.

**Mitigation:**
Changed `ssl_verify` default from `"no"` to `"yes"`. All connections to OIDC providers now verify TLS certificates by default.

---

### 2. HTTP Response Splitting Prevention

**Severity:** Critical

**Attack Pattern:**
The `WWW-Authenticate` header included unsanitized error messages from the OIDC library. An attacker crafting a malicious token could cause error messages containing CRLF sequences (`\r\n`) to be returned, enabling HTTP Response Splitting. This allows injection of arbitrary headers (e.g., `Set-Cookie`) or response body content.

**Mitigation:**
Added `sanitize_header_value()` function that strips CR, LF, and NULL bytes, and escapes quotes before inserting values into HTTP headers.

---

### 3. Header Spoofing Prevention

**Severity:** Critical

**Attack Pattern:**
The plugin sets headers like `X-USERINFO`, `X-ID-Token`, and `X-Access-Token` to pass authentication data to upstream services. If an attacker finds a path that bypasses OIDC authentication (via `ignore_auth_filters` or filter bypass techniques), they could send pre-crafted headers that the upstream service would trust, gaining unauthorized access with arbitrary identity claims.

**Mitigation:**
Added `clear_sensitive_headers()` function called at the **start** of every request, before any authentication logic. This ensures spoofed headers are always cleared, regardless of the authentication path taken.

---

### 4. Sensitive Token Logging Removed

**Severity:** High

**Attack Pattern:**
Full ID tokens were logged at DEBUG level, exposing PII (name, email, groups, custom claims) in log files. An attacker with access to logs (via log aggregation systems, file access, or log injection) could harvest user information, violating privacy regulations and enabling targeted attacks.

**Mitigation:**
Replaced full token logging with safe metadata logging that only records `sub`, `email`, and `exp` claims—sufficient for debugging without exposing the complete token payload.

---

### 5. JWT Time Leeway Reduced

**Severity:** High

**Attack Pattern:**
A 120-second leeway on JWT expiration validation extends the window for token replay attacks. An attacker who captures a valid token (via XSS, network interception, or log exposure) has an additional 2 minutes after the token's stated expiration to use it.

**Mitigation:**
Reduced JWT leeway from 120 seconds to 30 seconds. This provides sufficient tolerance for reasonable clock skew while minimizing the replay attack window.

---

### 6. Credential Object Mutation Fixed

**Severity:** Medium

**Attack Pattern:**
The `setCredentials()` function modified the original user object by reference instead of creating a copy. This could cause the modified object (with injected `id` and `username` fields) to propagate to other parts of the code that expect the original OIDC claims, potentially causing authorization decisions based on corrupted data.

**Mitigation:**
`setCredentials()` now creates a shallow copy of the user object before modification, preserving the integrity of the original claims.

---

### 7. Session Configuration Fail-Closed

**Severity:** Medium

**Attack Pattern:**
When session configuration JSON parsing failed, the plugin silently fell back to an empty configuration. This could result in sessions being created without intended security settings (e.g., missing `cookie_secure`, wrong `same_site` policy), weakening session security without any visible error.

**Mitigation:**
`get_session_opts()` now returns an error on parse failure. The handler checks for this error and returns HTTP 500, ensuring misconfigurations are immediately visible rather than silently degrading security.

---

### 8. Filter Bypass Prevention

**Severity:** High

**Attack Pattern:**
The filter matching used simple `string.find()` on the raw URI without normalization. Attackers could bypass authentication filters using:

- URL encoding (`/%6Cogout` instead of `/logout`)
- Path traversal sequences (`/foo/../logout`)
- Case variations (`/LOGOUT` vs `/logout`)
- Double slashes (`//logout`)

This allowed unauthenticated access to protected endpoints by crafting URLs that evade filter patterns while still routing to the same handlers.

**Mitigation:**
Implemented `normalize_path()` function that decodes percent-encoding, normalizes path segments (removes `.` and `..` traversals), collapses multiple slashes, and lowercases the path before filter evaluation. Also improved pattern matching to use proper prefix matching, preventing substring attacks (e.g., filter `/api` no longer incorrectly matches `/api-v2`).

---

## Remaining Vulnerabilities

The following issues were identified but not yet mitigated:

### Session Secret Warning

**Severity:** High

**Issue:** When `KONG_SESSION_SECRET` environment variable is not set, sessions use default key derivation without warning. In clustered deployments, this causes session validation failures across nodes and weakens session security.

**Prerequisites for Attack:**

- Attacker needs knowledge of lua-resty-session's default key derivation internals
- Attacker needs ability to capture valid session cookies (via network interception, XSS, or access to browser storage)
- If the Kubernetes deployment lacks the `KONG_SESSION_SECRET` in the Pod spec or referenced Secret, all pods use predictable key material, enabling session forgery

**Recommendation:** Log a prominent warning when session secret is missing or insufficient length.

---

### Open Redirect Vulnerabilities

**Severity:** Medium

**Issue:** Parameters `recovery_page_path`, `redirect_after_logout_uri`, and `post_logout_redirect_uri` accept arbitrary URLs without validation. Misconfiguration could enable open redirect attacks for phishing.

**Prerequisites for Attack:**

- Attacker needs write access to Kong plugin configuration, which in Kubernetes requires one of:
  - Access to Kong Admin API (if exposed)
  - Permissions to modify `KongPlugin` Custom Resources in the cluster
  - Access to modify ConfigMaps or Secrets containing Kong declarative configuration
- Once misconfigured, the open redirect can be exploited by any external attacker to phish users by sending links through the trusted Kong domain

**Recommendation:** Validate redirect URIs to ensure they are relative paths or match an allowlist of trusted domains.

---

### Bearer JWT Audience Validation Gap

**Severity:** Medium

**Issue:** When `bearer_jwt_auth_enable` is set to `"yes"`, neither `client_id` nor `bearer_jwt_auth_allowed_auds` is required. If both are missing, audience validation may behave unexpectedly.

**Prerequisites for Attack:**

- Attacker needs a valid JWT issued by the same Keycloak realm but intended for a different client/application. This could be obtained by:
  - Having legitimate access to another application in the same Keycloak realm
  - Compromising any other client registered in the same realm
- Combined with a misconfiguration (missing audience restriction), the attacker can authenticate to this service using a token issued for a different application
- Alternatively, if Keycloak itself is compromised, attacker can issue arbitrary JWTs

**Recommendation:** Add schema validation requiring at least one audience source when bearer JWT auth is enabled.

---

## Security Configuration Checklist

For production deployments, ensure the following:

- [ ] `ssl_verify` is `"yes"` (now default)
- [ ] `KONG_SESSION_SECRET` environment variable is set with a 32-byte base64-encoded random value
- [ ] `session` config includes `cookie_secure: true`, `cookie_http_only: true`, `cookie_same_site: "Lax"`
- [ ] `disable_access_token_header` and `disable_id_token_header` are `"yes"` unless upstream requires them
- [ ] `ignore_auth_filters` patterns are as specific as possible to minimize bypass surface
- [ ] `bearer_jwt_auth_allowed_auds` is explicitly configured when using JWT auth
- [ ] DEBUG logging is disabled in production to prevent information leakage

---

## Reporting Security Issues

If you discover a security vulnerability in this plugin, please report it responsibly by contacting the maintainers directly rather than opening a public issue.
