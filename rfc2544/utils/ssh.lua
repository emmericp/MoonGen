local conf  = require "config"
local ssh   = require "utils.ffi.ssh"



local mod = {}
mod.__index = mod
local session = nil

function mod.addInterfaceIP(interface, ip, pfx)
    return mod.exec("ip addr add " .. ip .. "/" .. pfx .. " dev " .. interface)
end

function mod.delInterfaceIP(interface, ip, pfx)
    return mod.exec("ip addr del " .. ip .. "/" .. pfx .. " dev " .. interface)
end

function mod.clearIPFilters()
    return mod.exec("iptables --flush FORWARD")
end

function mod.addIPFilter(src, sPfx, dst, dPfx)
    return mod.exec("iptables -A FORWARD -s " .. src .. "/" .. sPfx .. " -d " .. dst .. "/" .. dPfx .. " -j DROP")
end

function mod.delIPFilter()
    return mod.exec("iptables -D FORWARD -s " .. src .. "/" .. sPfx .. " -d " .. dst .. "/" .. dPfx .. " -j DROP")
end

function mod.clearIPRoutes()
    return mod.exec("ip route flush table main")
end

function mod.addIPRoute(dst, pfx, gateway, interface)
    if gateway and interface then
        return mod.exec("ip route add " .. dst .. "/" .. pfx .. " via " .. gateway .. " dev " .. interface)
    elseif gateway then
        return mod.exec("ip route add " .. dst .. "/" .. pfx .. " via " .. gateway)
    elseif interface then
        return mod.exec("ip route add " .. dst .. "/" .. pfx .. " dev " .. interface)
    else
        return -1
    end
end

function mod.delIPRoute()
    if gateway and interface then
        return mod.exec("ip route del " .. dst .. "/" .. pfx .. " via " .. gateway .. " dev " .. interface)
    elseif gateway then
        return mod.exec("ip route del " .. dst .. "/" .. pfx .. " via " .. gateway)
    elseif interface then
        return mod.exec("ip route del " .. dst .. "/" .. pfx .. " dev " .. interface)
    else
        return -1
    end   
end

function mod.getIPRouteCount()
    local ok, res = mod.exec("ip route show | wc -l")
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
--[[
function exec(cmd)
    local sess, err = getSession()
    if not sess or err ~= 0  then
        return err
    end
    cmd_res = ssh.request_exec(sess, cmd)
    return tonumber(ssh.request_exec(sess, "echo $?")), cmd_res
end
--]]

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
        
        -- could get banner to guess system
        -- (Mikrotik)
        -- ssh.get_issue_banner(session)
        session = session
    end
    return session, 0
end


return mod
