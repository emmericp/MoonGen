local snmpc = require "utils.snmpc"
local conf = require "config"

local mod = {}
mod.__index = mod

local session = nil

function mod.addInterfaceIP(interface, ip, pfx)
    return session:addIp(ip, pfx, interface)
end

function mod.delInterfaceIP(interface, ip, pfx)
    return session:delIp(ip, pfx, interface)
end

function mod.clearIPFilters()
    return -1
end

function mod.addIPFilter(src, sPfx, dst, dPfx)
    return -1
end

function mod.delIPFilter(src, sPfx, dst, dPfx)
    return -1
end

function mod.clearIPRoutes()
    return -1
end

function mod.addIPRoute(dst, pfx, gateway, interface)
    return session:addRouteEntry(dst, pfx, gateway, inteface, 4)
end

function mod.delIPRoute(dst, pfx, gateway, interface)
    return session:deleteRouteEntry(dst, pfx, gateway)
end

function mod.getIPRouteCount()
    return -1
end

function mod.getSession()
    if not session then
        session = snmp.session(conf.getHost(), snmpc.version2c, conf.getSNMPComm())
    end
    return session
end


return mod

