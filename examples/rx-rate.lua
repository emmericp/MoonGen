local mg		= require "moongen"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local utils 	= require "utils"
local log		= require "log"

local arp		= require "proto.arp"
local ip		= require "proto.ip4"
local icmp		= require "proto.icmp"


function master(...)
	if not ... then
		log:fatal("usage: port:ip [port:ip...]")
	end
	for _,arg in ipairs({...}) do
		port, ip = string.gmatch(arg, "(%g+):(%g+)")()
		port = tonumber(port)
		if not port or not ip then
			log:fatal("usage: port:ip [port:ip...]")
		end

		local dev = device.config{ port = port, rxQueues = 2, txQueues = 2 }
		device.waitForLinks()

		mg.startTask(arp.arpTask, {
			{ rxQueue = dev:getRxQueue(1), txQueue = dev:getTxQueue(1), ips = { ip } }
		})

		mg.startTask("rxCount", dev)
	end
	mg.waitForTasks()
end


function rxCount(dev)
	local rxCtr = stats:newDevRxCounter(dev)
	while mg.running() do
		rxCtr:update()
	end
	rxCtr:finalize()
end

