local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local dpdkc		= require "dpdkc"
local filter	= require "filter"
local ffi		= require "ffi"

ffi.cdef[[
	uint32_t rte_mempool_count(void* mp);
]]

local C = ffi.C

local PORT = 0

function master(...)
	local dev = device.config(PORT)
	local queue = dev:getTxQueue(0)
	dev:wait()
	dpdk.launchLua("task", queue)
	dpdk.waitForSlaves()
end

function task(queue)
	local mempool = memory.createMemPool(function(buf)
		local pkt = buf:getUdpPacket()
		pkt.payload.uint32[0] = 1
	end)
	local bufs = mempool:bufArray()
	bufs:alloc(60)
	queue:send(bufs)
	dpdk.sleepMillis(50)
	queue:stop()
	queue:start()
	assert(C.rte_mempool_count(mempool) == 2047)
	queue.dev:getTxQueue(5)
end

