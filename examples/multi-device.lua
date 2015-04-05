local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"

function master(...)
	local devs = { tonumberall(...) }
	map(devs, function(port)
		return device.config(port)
	end)
	device.waitForLinks()
	for i, v in ipairs(devs) do
		dpdk.launchLua("loadSlave", v.id)
	end
	dpdk.waitForSlaves()
end

function loadSlave(port)
	local queue = device.get(port):getTxQueue(0)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill({
			pktLength = 60
		})
	end)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(63)
	while dpdk.running() do
		bufs:alloc(60)
		bufs:offloadUdpChecksums()
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("[Device %d] Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", port, totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("[Device %d] Sent %d packets", port, totalSent)
end

