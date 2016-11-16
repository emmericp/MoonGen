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
	local dev1 = dev.config(port1)
	local dev2 = dev.config(port2)
	local q1 = dev1:getRxQueue(0)
	local q2 = dev2:getRxQueue(0)
	dev.waitForLinks()
	
	-- this starts the clock
	q1:enableTimestamps()
	q2:enableTimestamps()
	ts.syncClocks(dev1, dev2)
	print("Clock difference in nanoseconds, one value per second")
	print("Caution: this contains some systematic error in the microsecond-range as the clocks are read sequentially")
	print("Only use these values to determine clock drift")
	print("Note: the timestamper re-sycns the clocks between every packet by default to avoid potential drift. See code.")
	while dpdk.running() do
		dpdk.sleepMillis(1000, true)
		print(dev1:readTime() - dev2:readTime())
	end
end

