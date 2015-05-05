local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local timer		= require "timer"

memory.enableCache()

local RUN_TIME = 10

-- TODO: this
function master(port1, port2)
	if not port1 or not port2 then
		return print("Usage: port1 port2")
	end
	local dev1 = device.config(port1)
	local dev2 = device.config(port2)
	device.waitForLinks()
	for size = 60, 1518 do
		print("Running test for packet size = " .. size)
		local tx = dpdk.launchLua("loadSlave", dev1:getTxQueue(0), size)
		local rx = dpdk.launchLua("rxSlave", dev2:getRxQueue(0), size)
		tx:wait()
		local avgRx = rx:wait()
		if not dpdk.running() then
			break
		end
	end
	dpdk.waitForSlaves()
end


function loadSlave(queue, size)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = size,
			ethSrc = queue,
			ethDst = "10:11:12:13:14:15",
		}
	end)
	local bufs = mem:bufArray()
	local ctr = stats:newDevTxCounter(queue.dev, "plain")
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running() do
		bufs:alloc(size)
		queue:send(bufs)
		ctr:update()
	end
	ctr:finalize()
	return nil -- TODO
end

function rxSlave(queue, size)
	local bufs = memory.bufArray()
	local ctr = stats:newManualRxCounter(queue.dev, "plain")
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running() do
		local rx = queue:tryRecv(bufs, 10)
		bufs:freeAll()
		ctr:updateWithSize(rx, size)
	end
	ctr:finalize()
	return nil -- TODO
end

