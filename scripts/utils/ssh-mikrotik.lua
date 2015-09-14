local conf  = require "config"
local ssh   = require "utils.ffi.ssh"


local mod = {}
mod.__index = mod
local session = nil

function mod.addInterfaceIP(interface, ip, pfx)
    return mod.exec("/ip address add address=" .. ip .. "/" .. pfx .. " interface=" .. interface)
end

function mod.delInterfaceIP(interface, ip, pfx)
    return mod.exec("/ip address remove [/ip address find address=\"" .. ip .. "/" .. pfx .. "\" interface=" .. interface .. "]")
end

function mod.clearIPFilters()
    return mod.exec("/ip firewall filter remove [/ip firewall filter find]")
end

function mod.addIPFilter(src, sPfx, dst, dPfx)
    return mod.exec("/ip firewall filter add chain=forward src-address=" .. src .. "/" .. sPfx .. " dst-address=" .. dst .. "/" .. dPfx .. " action=drop")
end

function mod.delIPFilter(src, sPfx, dst, dPfx)
    return mod.exec("/ip firewall filter remove [/ip firewall filter find chain=forward src-address=\"" .. src .. "/" .. sPfx .. "\" dst-address=\"" .. dst .. "/" .. dPfx .. "\" action=drop]")
end

function mod.clearIPRoutes()
    return -1
end

function mod.addIPRoute(dst, pfx, gateway, interface)
    if gateway then
        return mod.exec("/ip route add dst-address=" .. dst .. "/" .. pfx .. " gateway=" .. gateway)
    elseif interface then
        return mod.exec("/ip route add dst-address=" .. dst .. "/" .. pfx .. " gateway=" .. interface)
    else
        return -1
    end
end

function mod.delIPRoute()
    if gateway and interface then
        return mod.exec("/ip route remove [/ip route find dst-address=" .. dst .. "/" .. pfx .. " gateway=" .. gateway .. "]")
    elseif interface then
        return mod.exec("/ip route remove [/ip route find dst-address=" .. dst .. "/" .. pfx .. " gateway=" .. interface .. "]")
    else
        return -1
    end   
end

function mod.getIPRouteCount()
    local ok, res = mod.exec("/ip route print count-only")
    return ok, tonumber(res)
end


function mod.exec(cmd)
    local sess, err = mod.getSession()
    if not sess or err ~= 0 then
        return -1, err
    end
    cmd_res, rc = ssh.request_exec(sess, cmd)
    if cmd_res == nil then
        print(rc)
        return -1, rc
    end
    return rc, cmd_res
end

function mod.getSession()
    if not session then
        print("ssh: establishing new connection")
        session = ssh.new()
        if session == nil then
            return nil, -1
        end
        ssh.set_option(session, "user", conf.getSSHUser())
        ssh.set_option(session, "host", conf.getHost())
        ssh.set_option(session, "port", conf.getSSHPort())
        -- do not ask for checking host signature
        ssh.set_option(session, "strict_hostkey", false)
        
        ssh.connect(session)
        local ok = ssh.auth_autopubkey(session)
        if not ok then
            ok = ssh.auth_password(session, conf.getSSHPass()) 
        end
        
        if not ok then
            return nil, -1
        end
    end
    return session, 0
end


return mod
