local dpdk		= require "dpdk"
local dpdkc		= require "dpdkc"
local device	= require "device"

local function assertSame(a, b)
	if a ~= b then 
		print(a, b)
	end
	assert(a == b)
end

function master()
	for i = 1, 100 do
		for i = 1, 3 do
			dpdk.launchLua("emptyTask")
		end
		dpdk.sleepMillis(10)
		-- this will fail if there is something wrong with recycling
	end
	
	local task = dpdk.launchLua("passThroughTask", "string", 2, 3)
	local a, b, c = task:wait()
	assertSame(a, "string")
	assertSame(b, 2)
	assertSame(c, 3)
	
	local task = dpdk.launchLua("passThroughTask", { hello = "world", nil, 5, { 1 } })
	local a = task:wait()
	assertSame(a.hello, "world")
	assertSame(a[2], 5)
	assertSame(a[3][1], 1)
	
	local task = dpdk.launchLua("passThroughTask", device.get(0), device.get(0):getRxQueue(15))
	local dev, rxQueue = task:wait()
	assertSame(dev.id, 0)
	assertSame(getmetatable(dev), device.__devicePrototype)
	assertSame(rxQueue.qid, 15)
	assertSame(getmetatable(rxQueue), device.__rxQueuePrototype)
	
	-- check that dpdk.launchLua is not implemented as function launchLua(...) return ... end ;)
	assertSame(dpdk.launchLua("addOneTask", 5):wait(), 6)
	
	-- nil values are tricky as simply unpack()ing the serialized arg array won't work
	local task = dpdk.launchLua("passThroughTask", nil, 1)
	local _, val = task:wait()
	assertSame(val, 1)

	local task = dpdk.launchLua("passThroughTask", 1, nil, nil, nil, nil, nil, nil, nil, 9)
	assertSame(select(9, task:wait()), 9)
end

function emptyTask()
end

function passThroughTask(...)
	return ...
end

function addOneTask(val)
	return val + 1
end
