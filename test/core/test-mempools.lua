local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local dpdkc		= require "dpdkc"
local filter	= require "filter"
local ffi		= require "ffi"

ffi.cdef[[
	uint32_t rte_mempool_count(void* mp);
	int rte_eth_dev_tx_queue_start(uint8_t port_id, uint16_t rx_queue_id);
	int rte_eth_dev_tx_queue_stop(uint8_t port_id, uint16_t rx_queue_id);
]]

local C = ffi.C

-- TODO: update test to test the actual functionality once it is implemented
function master(...)
	local dev = device.config(8)
	local queue = dev:getTxQueue(0)
	dev:wait()
	local mempool = memory.createMemPool(function(buf)
		local pkt = buf:getUdpPacket()
		pkt.payload.uint32[0] = 1
	end)
	print(C.rte_mempool_count(mempool))
	local bufs = mempool:bufArray()
	bufs:alloc(60)
	print(C.rte_mempool_count(mempool))
	queue:send(bufs)
	print(C.rte_mempool_count(mempool))
	dpdk.sleepMillis(50)
	print("before stop", C.rte_mempool_count(mempool))
	print(C.rte_eth_dev_tx_queue_stop(8, 0))
	print("after stop", C.rte_mempool_count(mempool))
	print(C.rte_eth_dev_tx_queue_start(8, 0))
	print("after start", C.rte_mempool_count(mempool))
	assert(C.rte_mempool_count(mempool) == 2047)
end


