local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local dpdkc		= require "dpdkc"
local filter	= require "filter"
local ffi		= require "ffi"

ffi.cdef[[
	uint32_t rte_mempool_count(void* mp);
]]

memory.enableCache()

local C = ffi.C

local PORT = 0

function master(...)
	local dev = device.config(PORT)
	local queue = dev:getTxQueue(0)
	dev:wait()
	local poolId = dpdk.launchLua("task", queue):wait()
	dpdk.launchLua("reclaimTask", poolId):wait()
end

function task(queue)
	local mempool = memory.createMemPool(function(buf)
		local pkt = buf:getUdpPacket()
		pkt.payload.uint32[0] = 0x1234
	end)
	local bufs = mempool:bufArray()
	bufs:alloc(60)
	queue:send(bufs)
	dpdk.sleepMillis(50)
	queue:stop()
	queue:start()
	assert(C.rte_mempool_count(mempool) == 2047)
	queue.dev:getTxQueue(5)
	local bufs = {}
	for i = 1, 2047 do
		bufs[#bufs + 1] = mempool:alloc(60)
	end
	assert(bufs[2047] ~= nil)
	for i = 1, 2047 do
		dpdkc.rte_pktmbuf_free_export(bufs[i])
	end
	-- important: pass this as a string as a future version will disable caching
	-- for pools that are serialized (i.e. used by multiple cores)
	return tostring(mempool)
end

function reclaimTask(poolAddr)
	local numBufs = 0
	local mempool = memory.createMemPool(function(buf)
		local pkt = buf:getUdpPacket()
		assert(pkt.payload.uint32[0] == 0)
		numBufs = numBufs + 1
	end)
	assert(numBufs == 2047)
	assert(C.rte_mempool_count(mempool) == 2047)
	assert(poolAddr == tostring(mempool))
end

