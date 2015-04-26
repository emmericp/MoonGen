local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"

function master(numCores, ...)
	local devices = { ... }
	if not numCores or #devices == 0 then
		return print("Usage: numCores port [port...]")
	end
	map(devices, function(dev) return device.config(dev, 1, numCores) end)
	device.waitForLinks()
	for i = 0, numCores - 1 do
		dpdk.launchLua("loadSlave", devices, i, 256)
	end
	-- TODO: the main core is wasted for stats tracking, this could be optimized
	-- (e.g. with DPDK 2.0)
	counterSlave(devices)
	dpdk.waitForSlaves()
end

function counterSlave(devices)
	local counters = {}
	for i, dev in ipairs(devices) do
		counters[i] = stats:newDevTxCounter(dev, "plain")
	end
	while dpdk.running() do
		for _, ctr in ipairs(counters) do
			ctr:update()
		end
		dpdk.sleepMillisIdle(10)
	end
	for _, ctr in ipairs(counters) do
		ctr:update()
	end
end


function loadSlave(devices, taskId, numFlows)
	local queues = {}
	local mems = {}
	local bufs = {}
	for i, dev in ipairs(devices) do
		queues[i] = dev:getTxQueue(taskId)
		mems[i] = memory.createMemPool(function(buf)
			buf:getUdpPacket():fill{
				pktLength = 60,
				ethSrc = queues[i],
				ethDst = "10:11:12:13:14:15",
				ipDst = "192.168.1.1",
				udpSrc = 1234,
				udpDst = 5678,
			}
		end)
		bufs[i] = mems[i]:bufArray(128)
	end
	local baseIP = parseIPAddress("10.0.0.1")
	local counter = 0
	while dpdk.running() do
		for i = 1, #queues do
			local queue = queues[i]
			local bufs = bufs[i]
			bufs:alloc(60)
			-- + 2.5% performance over ipairs in this example
			-- (don't do this in a normal script, not worth it)
			for i = 0, bufs.size - 1 do
				local buf = bufs.array[i]
				local pkt = buf:getUdpPacket()
				pkt.ip.src:set(baseIP + counter)
				counter = incAndWrap(counter, numFlows)
			end
			-- UDP checksums are optional, so just IP checksums are sufficient here
			bufs:offloadIPChecksums()
			queue:send(bufs)
		end
	end
end

