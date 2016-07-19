local mg			= require "dpdk"
local memory		= require "memory"
local device		= require "device"
local stats			= require "stats"
local histogram		= require "histogram"
local log			= require "log"
local timer			= require "timer"


function master(rxPort, saveInterval)
	if not rxPort then
		return log:info("usage: rxPort")
	end
	local rxDev = device.config{ port = rxPort, dropEnable = false }
	device.waitForLinks()
	mg.launchLua("dumpSlave", rxDev:getRxQueue(0))
	mg.waitForSlaves()
end


function dumpSlave(queue)
	local bufs = memory.bufArray()
	local pktCtr = stats:newPktRxCounter("Packets counted", "plain")
	while mg.running() do
		local rx = queue:tryRecv(bufs, 100)
		for i = 1, rx do
			local buf = bufs[i]
			buf:dump()
			pktCtr:countPacket(buf)
		end
		bufs:free(rx)
		pktCtr:update()
	end
	pktCtr:finalize()
end

