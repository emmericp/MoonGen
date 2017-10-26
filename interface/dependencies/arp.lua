local arp = require "proto.arp"

local dependency = {}

function dependency.env(env)
	function env.arp(ip, fallback, timeout)
		return { "arp", ip, fallback, timeout or 5 }
	end
end

local function macString(addr)
	if type(addr) == "number" then
		local mac = require("ffi").new("union mac_address")
		mac:set(addr)
		return mac:getString()
	elseif type(addr) == "cdata" then
		return addr:getString()
	end

	return addr
end

-- luacheck: globals ipString
function ipString(addr)
	if type(addr) == "number" then
		addr = ip4ToString(addr) -- luacheck: read globals ip4ToString
	elseif type(addr) == "cdata" then
		addr = addr:getString(true)
	end

	return addr
end

function dependency.debug(tbl)
	local addr = ipString(tbl[2])

	if tbl[3] then
		return string.format("Arp result for ip '%s', fallback to '%s'.", addr, macString(tbl[3]))
	else
		return string.format("Arp result for ip '%s'.", addr)
	end
end

function dependency.getValue(_, tbl)
	return arp.blockingLookup(tbl[2], tbl[4]) or tbl[3]
end

return dependency
