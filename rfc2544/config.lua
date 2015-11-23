local ns = require "namespaces"

local DEFAULT_SSH_USER  = "root"
local DEFAULT_SSH_PORT  = 22
local DEFAULT_SSH_HOST  = "localhost"
local DEFAULT_SSH_PASS  = "password"

local DEFAULT_SNMP_COMM = "public"


local mod = {}
mod.__index = mod

local config = ns.get()

function mod.getSSHPort()
    return config.sshPort or DEFAULT_SSH_PORT
end

function mod.setSSHPort(port)
    config.sshPort = port
end

function mod.getHost()
    return config.host or DEFAULT_SSH_HOST
end

function mod.setHost(host)
    config.host = host
end

function mod.getSSHUser()
    return config.sshUser or DEFAULT_SSH_USER
end

function mod.setSSHUser(user)
    config.sshUser = user
end

function mod.getSSHPass()
    return config.sshPass or DEFAULT_SSH_PASS
end

function mod.setSSHPass(pass)
    config.sshPass = pass
end

function mod.getSNMPComm()
    return config.snmpComm or DEFAULT_SNMP_COMM
end

function mod.setSNMPComm(comm)
    config.snmpComm = comm
end

return mod