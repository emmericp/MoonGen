local dpdk	= require "dpdk"
local memory	= require "memory"
local dev	= require "device"
local dpdkc	= require "dpdkc"
local ts	= require "timestamping"
local ffi	= require "ffi"

function master(...)
	local port1, port2 = tonumberall(...)
	if not port1 or not port2 then
		errorf("usage: port1 port2")
	end
	local mempool = memory.createMemPool()
	local dev1 = dev.config(port1, mempool)
	local dev2 = dev.config(port2, mempool)
	local q1 = dev1:getRxQueue(0)
	local q2 = dev2:getRxQueue(0)
	dev.waitForLinks()
	
	-- this starts the clock
	q1:enableTimestamps()
	q2:enableTimestamps()
	ts.syncClocks(dev1, dev2)
	while dpdk.running() do
		dpdk.sleepMillis(1000, true)
		print(ts.getClockDiff(dev1, dev2))
	end
end

