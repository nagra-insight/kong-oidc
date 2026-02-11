local M = {}

-- Cache the env var at module load time
local SESSION_SECRET = os.getenv("KONG_SESSION_SECRET")

-- Get the decoded session secret for lua-resty-session v4.x
-- Returns the secret to be included in session_opts
function M.get_secret()
    if not SESSION_SECRET then
        return nil
    end

    local decoded_session_secret = ngx.decode_base64(SESSION_SECRET)
    if not decoded_session_secret then
        kong.log.err("Invalid session secret from env var KONG_SESSION_SECRET, could not be decoded")
        return nil
    end

    return decoded_session_secret
end

-- Configure session options with the secret
-- Returns session_opts table with secret included
function M.configure(session_opts)
    local secret = M.get_secret()
    if secret then
        -- For lua-resty-session v4.x, we pass the secret in the configuration table
        -- If the decoded secret is exactly 32 bytes, use it as ikm directly
        -- Otherwise, use it as secret (will be hashed with SHA-256)
        if #secret == 32 then
            session_opts.ikm = secret
        else
            session_opts.secret = secret
        end
    end
    return session_opts
end

return M
