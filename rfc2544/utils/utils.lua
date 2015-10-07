local actors = {}
local status, snmp = pcall(require, 'utils.snmp')
if status then
    table.insert(actors, snmp)
else
    print "unable to load snmp module"
end

local status, sshMikrotik = pcall(require, 'utils.ssh-mikrotik')
if status then
    table.insert(actors, sshMikrotik)
else
    print "unable to load mikrotik ssh module"
end

local status, sshFreeBSD = pcall(require, 'utils.ssh-freebsd')
if status then                                                                  
    table.insert(actors, sshFreeBSD)
else
    print "unable to load freeBSD ssh module"
end

local status, ssh = pcall(require, 'utils.ssh')
if status then
    table.insert(actors, ssh)
else
    print "unable to load linux ssh module"
end

local manual = require "utils.manual"
table.insert(actors, manual)

local mod = {}
mod.__index = mod

function mod.addInterfaceIP(interface, ip, pfx)
    local status = -1
    for k, actor in ipairs(actors) do
        status = actor.addInterfaceIP(interface, ip, pfx)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.delInterfaceIP(interface, ip, pfx)
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.delInterfaceIP(interface, ip, pfx)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.clearIPFilters()
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.clearIPFilters()
        if status == 0 then
            break
        end
    end
    return status
end

function mod.addIPFilter(src, sPfx, dst, dPfx)
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.addIPFilter(src, sPfx, dst, dPfx)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.delIPFilter(src, sPfx, dst, dPfx)
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.delIPFilter(src, sPfx, dst, dPfx)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.clearIPRoutes()
    local status = -1
    for _, actor in ipairs(actors) do
        actor.clearIPRoutes()
        if status == 0 then
            break
        end
    end
    return status
end

function mod.addIPRoute(dst, pfx, gateway, interface)
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.addIPRoute(dst, pfx, gateway, interface)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.delIPRoute(dst, pfx, gateway, interface)
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.delIPRoute(dst, pfx, gateway, interface)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.addIPRouteRange(firstIP, lastIP)
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.addIPRouteRange(firstIP, lastIP)
        if status == 0 then
            break
        end
    end
    return status
end

function mod.getIPRouteCount()
    local status = -1
    for _, actor in ipairs(actors) do
        status = actor.getIPRouteCount()
        if status == 0 then
            break
        end
    end
    return status
end

function mod.getDeviceName()
    return manual.getDeviceName()
end

function mod.getDeviceOS()
    return manual.getDeviceOS()
end




local binarySearch = {}
binarySearch.__index = binarySearch

function binarySearch:create(lower, upper)
    local self = setmetatable({}, binarySearch)
    self.lowerLimit = lower
    self.upperLimit = upper
    return self
end
setmetatable(binarySearch, { __call = binarySearch.create })

function binarySearch:init(lower, upper)
    self.lowerLimit = lower
    self.upperLimit = upper
end

function binarySearch:next(curr, top, threshold)
    if top then
        if curr == self.upperLimit then
            return curr, true
        else
            self.lowerLimit = curr
        end
    else
        if curr == lowerLimit then            
            return curr, true
        else
            self.upperLimit = curr
        end
    end
    local nextVal = math.ceil((self.lowerLimit + self.upperLimit) / 2)
    if math.abs(nextVal - curr) < threshold then
        return curr, true
    end
    return nextVal, false
end

mod.binarySearch = binarySearch


mod.modifier = {
    none = 0,
    randEth = 1,
    randIp = 2
}

function mod.getPktModifierFunction(modifier, baseIp, wrapIp, baseEth, wrapEth)
    local foo = function() end
    if modifier == mod.modifier.randEth then
        local ethCtr = 0
        foo = function(pkt)
            pkt.ip.dst:setNumber(baseEth + ethCtr)
            ethCtr = incAndWrap(ethCtr, wrapEth)
        end
    elseif modifier == mod.modifier.randIp then
        local ipCtr = 0
        foo = function(pkt)
            pkt.ip.dst:set(baseIP + ipCtr)
            ipCtr = incAndWrap(ipCtr, wrapIp)
        end
    end
    return foo
end
--[[
bit faster then macAddr:setNumber or macAddr:set
and faster then macAddr:setString
but still not fast enough for one single slave and 10GbE @64b pkts
set destination MAC address
ffi.copy(macAddr, pkt.eth.dst.uint8, 6)
macAddr[0] = (macAddr[0] + 1) % macWraparound
--]]

function mod.parseArguments(args)
    local results = {}
    for i=1, #args, 2 do
        local key = args[i]:gsub("-", "", 2) -- cut off one or two leading minus
        results[key] = args[i+1]
    end
    return results
end



return mod


