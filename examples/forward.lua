local dpdk	= require "dpdk"
local memory	= require "memory"
local dev	= require "device"
local dpdkc	= require "dpdkc"

local ffi	= require "ffi"

function master(...)
	local rxPort, txPort = tonumberall(...)
	-- TODO: NUMA-aware mempool allocation
	local mempool = memory.createMemPool(2048)
	dev.config(rxPort, mempool)
	if rxPort ~= txPort then
		dev.config(txPort, mempool)
	end
	dev.waitForPorts(rxPort, txPort)
	dpdk.launchLua("slave", rxPort, txPort, mempool)
	dpdk.waitForSlaves()
end

function slave(rxPort, txPort, mempool)
	local burstSize = 16
	local bufs = ffi.new("struct rte_mbuf*[?]", burstSize)
	while true do
		local n = dpdkc.rte_eth_rx_burst_export(rxPort, 0, bufs, burstSize)
		if n ~= 0 then
			-- send
			local sent = dpdkc.rte_eth_tx_burst_export(txPort, 0, bufs, n) 
			for i = sent, n - 1 do
				dpdkc.rte_pktmbuf_free_export(bufs[i])
			end
		end
	end
end

