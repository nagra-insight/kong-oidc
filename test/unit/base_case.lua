package.path = package.path .. ";test/lib/?.lua;;" -- kong & co

-- Initialize minimal ngx global for Kong 3.9 constants module
-- Kong's constants.lua expects these to be available at module load time
if not _G.ngx then
    _G.ngx = {
        DEBUG = 7,
        INFO = 6,
        NOTICE = 5,
        WARN = 4,
        ERR = 3,
        CRIT = 2,
        ALERT = 1,
        EMERG = 0,
    }
end

local Object = require "test.unit.classic"
local BaseCase = Object:extend()


function BaseCase:setUp()
end

function BaseCase:tearDown()
end

return BaseCase
