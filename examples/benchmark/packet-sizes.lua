local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local timer		= require "timer"

memory.enableCache()

-- TODO: this
function master(port1, port2)
	if not port1 or not port2 then
		return print("Usage: port1 port2")
	end
	local dev2 = device.config(port1)
	local dev1 = device.config(port2)
	device.waitForLinks()
	for size = 60, 1518 do
		print("Running test for packet size = " .. size)
		local task = dpdk.launchLua("loadSlave", dev1:getTxQueue(0), dev2:getTxQueue(0), size)
		local avg = task:wait()
		if not dpdk.running() then
			break
		end
	end
	dpdk.waitForSlaves()
end


function loadSlave(queue1, queue2, size)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = size,
			ethSrc = queue,
			ethDst = "10:11:12:13:14:15",
		}
	end)
	bufs = mem:bufArray()
	local ctr1 = stats:newDevTxCounter(queue1.dev, "plain")
	local ctr2 = stats:newDevTxCounter(queue2.dev, "plain")
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running() do
		bufs:alloc(size)
		queue1:send(bufs)
		ctr1:update()
		bufs:alloc(size)
		queue2:send(bufs)
		ctr2:update()
	end
	ctr1:finalize()
	ctr2:finalize()
	return nil -- TODO
end

