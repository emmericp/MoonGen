-- vim:ts=4:sw=4:noexpandtab
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local stats		= require "stats"
local hist		= require "histogram"

local PKT_SIZE	= 60
local ETH_DST	= "11:12:13:14:15:16"

function master(...)
	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		return print("usage: txPort rxPort [rate]")
	end
	rate = rate or 10000
	-- hardware rate control fails with small packets at these rates
	local numQueues = rate > 6000 and rate < 10000 and 3 or 1
	local txDev = device.config(txPort, 2, 4)
	local rxDev = device.config(rxPort, 2, 1) -- ignored if txDev == rxDev
	local queues = {}
	for i = 1, numQueues do
		local queue = txDev:getTxQueue(i)
		queues[#queues + 1] = queue
		if rate < 10000 then -- only set rate if necessary to work with devices that don't support hw rc
			queue:setRate(rate / numQueues)
		end
	end
	dpdk.launchLua("loadSlave", queues, txDev, rxDev)
	dpdk.launchLua("timerSlave", txDev:getTxQueue(0), rxDev:getRxQueue(1))
	dpdk.waitForSlaves()
end

function loadSlave(queues, txDev, rxDev)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local txCtr = stats:newDevTxCounter(txDev, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")
	while dpdk.running() do
		for i, queue in ipairs(queues) do
			bufs:alloc(PKT_SIZE)
			queue:send(bufs)
		end
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
end

function timerSlave(txQueue, rxQueue)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	dpdk.sleepMillis(1000) -- ensure that the load task is running
	while dpdk.running() do
		hist:update(timestamper:measureLatency(function(buf) buf:getEthernetPacket().eth.dst:setString(ETH_DST) end))
	end
	hist:print()
	hist:save("histogram.csv")
end

