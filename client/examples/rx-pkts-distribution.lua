local mg			= require "dpdk"
local memory		= require "memory"
local device		= require "device"
local stats			= require "stats"
local histogram		= require "histogram"
local log			= require "log"
local timer			= require "timer"


function master(rxPort, saveInterval)
	if not rxPort then
		return log:info("usage: rxPort [saveInterval]")
	end
	-- TODO: RSS?
	local saveInterval = saveInterval or 60
	local rxDev = device.config{ port = rxPort, dropEnable = false }
	device.waitForLinks()
	mg.launchLua("counterSlave", rxDev:getRxQueue(0), saveInterval)
	mg.waitForSlaves()
end


function counterSlave(queue, saveInterval)
	local bufs = memory.bufArray()
	local ctrs = {}
	local rxCtr = stats:newDevRxCounter(queue.dev)
	-- to track if we lose packets on the NIC
	local pktCtr = stats:newPktRxCounter("Packets counted", "plain")
	local hist = histogram:create()
	local timer = timer:new(saveInterval)
	while mg.running() do
		local rx = queue:tryRecv(bufs, 100)
		for i = 1, rx do
			local buf = bufs[i]
			local size = buf:getSize()
			hist:update(size)
			pktCtr:countPacket(buf)
		end
		bufs:free(rx)
		rxCtr:update()
		pktCtr:update()
		if timer:expired() then
			-- FIXME: this is really slow and might lose packets
			-- however, the histogram sucks and moving this to another thread would require a rewrite
			timer:reset()
			hist:print()
			hist:save("hist" .. time() .. ".csv")
		end
	end
	rxCtr:finalize()
	pktCtr:finalize()
	-- TODO: check the queue's overflow counter to detect lost packets
end

