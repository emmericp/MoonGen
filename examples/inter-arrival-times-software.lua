local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"


function master(...)
	local rxPort = tonumberall(...)
	if not rxPort then
		return print("usage: rxPort")
	end
	rxDev = device.config(rxPort, memory.createMemPool())
	rxDev:wait()
	local queue = rxDev:getRxQueue(0)
	local times = ts.readTimestampsSoftware(queue, 512)
	--for i = 0, 9 do
	--	print(times[i])
	--end
end

