local M = {}

-- Normalize URI path to prevent filter bypass attacks via URL encoding,
-- path traversal, case variations, or double slashes.
-- This normalization is applied before regex pattern matching.
local function normalize_path(path)
    if not path or path == "" then
        return "/"
    end

    -- Decode percent-encoded characters (handles %XX sequences)
    local decoded = ngx.unescape_uri(path)

    -- Lowercase for case-insensitive matching
    decoded = decoded:lower()

    -- Normalize multiple consecutive slashes to single slash
    decoded = decoded:gsub("//+", "/")

    -- Remove /./ sequences (current directory references)
    while decoded:find("/./", 1, true) do
        decoded = decoded:gsub("/%./", "/")
    end

    -- Handle /../ sequences (parent directory traversal)
    -- Limit iterations to prevent infinite loops on malformed paths
    local iterations = 0
    local max_iterations = 100
    while decoded:find("/../", 1, true) and iterations < max_iterations do
        -- Replace /something/../ with /
        local new_decoded = decoded:gsub("/[^/]+/%.%./", "/", 1)
        if new_decoded == decoded then
            -- No replacement made, break to avoid infinite loop
            break
        end
        decoded = new_decoded
        iterations = iterations + 1
    end

    -- Remove leading /../ sequences (attempting to go above root)
    decoded = decoded:gsub("^/%.%./", "/")
    while decoded:match("^/%.%./") do
        decoded = decoded:gsub("^/%.%./", "/")
    end

    -- Remove trailing /.
    decoded = decoded:gsub("/%.$", "/")

    -- Ensure path starts with /
    if decoded:sub(1, 1) ~= "/" then
        decoded = "/" .. decoded
    end

    return decoded
end

-- Check if request should be ignored based on filter patterns.
-- Patterns are Lua patterns (regex) matched against the normalized URI.
local function shouldIgnoreRequest(patterns)
    if not patterns or #patterns == 0 then
        return false
    end

    local normalized_uri = normalize_path(ngx.var.uri)

    for _, pattern in ipairs(patterns) do
        -- Convert pattern to lowercase for case-insensitive matching
        local normalized_pattern = pattern:lower()
        local isMatching = not (string.find(normalized_uri, normalized_pattern) == nil)
        if isMatching then
            return true
        end
    end

    return false
end

function M.shouldProcessRequest(config)
    return not shouldIgnoreRequest(config.filters)
end

return M
