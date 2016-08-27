-- vim:ts=4:sw=4:noexpandtab
--- How to configure RSS
local dpdk   = require "dpdk"
local memory = require "memory"
local device = require "device"
local stats  = require "stats"
local log    = require "log"

local PKT_SIZE  = 60
local NUM_FLOWS = 100

function master(txPort, rxPort, rxQueues)
	if not txPort or not rxPort then
		log:info("Usage: txPort rxPort [rxQueues]")
		return
	end
	rxQueues = rxQueues or 2
	local txDev = device.config{port = txPort}
	local rxDev = device.config{
		port = rxPort,
		rxQueues = rxQueues + 1,
		rssQueues = rxQueues,
		rssBaseQueue = 1 -- optional and defaults to 0
	}
	device.waitForLinks()
	dpdk.launchLua("txSlave", txDev:getTxQueue(0))
	for i = 1, rxQueues do
		dpdk.launchLua("rxSlave", rxDev:getRxQueue(i))
	end
	dpdk.waitForSlaves()
end

function txSlave(queue)
	local mempool = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			ethSrc = queue,
			pktLength = PKT_SIZE
		}
	end)
	local bufs = mempool:bufArray()
	local counter = 0
	local txCtr = stats:newDevTxCounter(queue, "plain")
	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.udp:setSrcPort(1000 + counter)
			counter = incAndWrap(counter, NUM_FLOWS)
		end
		bufs:offloadUdpChecksums()
		queue:send(bufs)
		txCtr:update()
	end
	txCtr:finalize()
end

function rxSlave(queue)
	local bufs = memory.bufArray()
	ctr = stats:newPktRxCounter(queue, "plain")
	while dpdk.running(100) do
		local rx = queue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			ctr:countPacket(buf)
		end
		ctr:update()
		bufs:free(rx)
	end
	ctr:finalize()
end

