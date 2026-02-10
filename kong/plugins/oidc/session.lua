local M = {}

-- Cache the env var at module load time
local SESSION_SECRET = os.getenv("KONG_SESSION_SECRET")

function M.configure(config)
    if SESSION_SECRET then
        local decoded_session_secret = ngx.decode_base64(SESSION_SECRET)
        if not decoded_session_secret then
            kong.log.err("Invalid session secret from env var KONG_SESSION_SECRET, could not be decoded")
            return kong.response.error(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end
        ngx.var.secret = decoded_session_secret
    end
end

return M
