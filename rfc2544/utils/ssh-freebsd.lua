local conf  = require "config"
local ssh   = require "utils.ffi.ssh"



local mod = {}
mod.__index = mod
local session = nil

function mod.addInterfaceIP(interface, ip, pfx)
    return mod.exec("ifconfig " .. interface .. " inet " .. ip .. "/" .. pfx .. " add")
end

function mod.delInterfaceIP(interface, ip, pfx)
    return mod.exec("ifconfig " .. interface .. " inet " .. ip .. " -alias")
end
-- The Firewall is not supported yet. Kernel must be recompiled first and the mod.addIPFilter and mod.delIPFilter 
-- cannot be translated in that extent
function mod.clearIPFilters()
    return mod.exec("ipf -Fa")
end

function mod.addIPFilter(src, sPfx, dst, dPfx)
    return mod.exec("printf \"block in from " .. src .. "/" .. sPfx .. " to " .. dst .. "/" .. dPfx .. "\nblock out from " .. src .. "/" .. sPfx .. " to " .. dst .. "/" .. dPfx .. "\" | ipf -f -")
end

function mod.delIPFilter()
    return -1
end

function mod.clearIPRoutes()
    return mod.exec("route flush")
end
--FreeBSD does not support interface
function mod.addIPRoute(dst, pfx, gateway, interface)
    if gateway and interface then
        return mod.exec("route add -net" .. dst .. "/" .. pfx .. gateway)
    elseif gateway then
        return mod.exec("route add -net" .. dst .. "/" .. pfx .. gateway)
    elseif interface then
        return mod.exec("route add -net" .. dst .. "/" .. pfx .. gateway)
    else
        return -1
    end
end
--Same here: FreeBSD does not support interface
function mod.delIPRoute()
    if gateway and interface then
        return mod.exec("route del " .. dst .. "/" .. pfx .. gateway)
    elseif gateway then
        return mod.exec("route del " .. dst .. "/" .. pfx .. gateway)
    elseif interface then
        return mod.exec("route del " .. dst .. "/" .. pfx .. gateway)
    else
        return -1
    end   
end
--I dont know if this works, since netstat displays comments
function mod.getIPRouteCount()
    local ok, res = mod.exec("netstat -rn -4 | wc -l")
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
