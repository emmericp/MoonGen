local mod = {}
mod.__index = mod

local namespaces = require "namespaces"
local ns = namespaces.get()

function confirm()
    local answer
    repeat
        io.write("continue (y/n)? ")
        answer = io.read()
    until answer == "y" or answer == "n"
    return answer == "y" and 0 or -1
end
    

function mod.addInterfaceIP(interface, ip, pfx)
    io.write(string.format("configure: add to interface %s ip %s/%d", interface, ip, pfx))
    return confirm()
end

function mod.delInterfaceIP(interface, ip, pfx)
    io.write(string.format("configure: delete from interface %s ip %s/%d", interface, ip, pfx))
    return confirm()
end

function mod.clearIPFilters()
    io.write("configure: clear IP Filters")
    return confirm()
end

function mod.addIPFilter(src, sPfx, dst, dPfx)
    io.write(string.format("configure: add ip filter from %s/%d to %s/%d", src, sPfx, dst, dPfx))
    return confirm()
end

function mod.delIPFilter(src, sPfx, dst, dPfx)
    io.write(string.format("configure: delete ip filter from %s/%d to %s/%d", src, sPfx, dst, dPfx))
    return confirm()
end

function mod.clearIPRoutes()
    io.write("configure: clear IP Routes")
    return confirm()
end

function mod.addIPRoute(dst, pfx, gateway, interface)
    io.write(string.format("configure: add route to %s/%d via %s dev %s", dst, pfx, gateway, interface))
    return confirm()
end

function mod.delIPRoute(dst, pfx, gateway, interface)
    io.write(string.format("configure: delte route to %s/%d via %s dev %s", dst, pfx, gateway, interface))
    return confirm()
end

function mod.getIPRouteCount()
    io.write("configure: get ip route count: ")
    return tonumber(io.read())
end

function mod.getDeviceName()
    if type(ns.deviceName) ~= string then
        io.write("configure: get device name: ")
        ns.deviceName = io.read()
    end
    return ns.deviceName
end

function mod.getDeviceOS()    
    if type(ns.deviceOS) ~= string then
        io.write("configure: get device OS: ")
        ns.deviceOS = io.read()
    end
    return ns.deviceOS
end

return mod
