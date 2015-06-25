local dpdk		= require "dpdk"
local memory	= require "memory"
local ts		= require "timestamping"
local device	= require "device"
local filter	= require "filter"
local stats		= require "stats"
local timer		= require "timer"
local histogram	= require "histogram"


local PKT_SIZE = 60

function master(...)
	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate (Mpps)]")
	end
	rate = rate or 2
	local txDev = device.config(txPort, 2, 2)
	local rxDev = device.config(rxPort, 2, 2)
	device.waitForLinks()
	dpdk.launchLua("loadSlave", txDev, rxDev, txDev:getTxQueue(0), rate, PKT_SIZE)
	dpdk.launchLua("timerSlave", txDev:getTxQueue(1), rxDev:getRxQueue(1), PKT_SIZE)
	dpdk.waitForSlaves()
end

function loadSlave(dev, rxDev, queue, rate, size)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	rxDev:l2Filter(0x1234, filter.DROP)
	local bufs = mem:bufArray()
	local rxStats = stats:newDevRxCounter(rxDev, "plain")
	local txStats = stats:newManualTxCounter(dev, "plain")
	while dpdk.running() do
		bufs:alloc(size)
		for _, buf in ipairs(bufs) do
			-- this script uses Mpps instead of Mbit (like the other scripts)
			buf:setDelay(poissonDelay(10^10 / 8 / (rate * 10^6) - size - 24))
			--buf:setRate(rate)
		end
		txStats:updateWithSize(queue:sendWithDelay(bufs), size)
		rxStats:update()
		--txStats:update()
	end
	rxStats:finalize()
	txStats:finalize()
end

function timerSlave(txQueue, rxQueue, size)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = histogram:new()
	-- wait for a second to give the other task a chance to start
	dpdk.sleepMillis(1000)
	local rateLimiter = timer:new(0.001)
	while dpdk.running() do
		rateLimiter:reset()
		hist:update(timestamper:measureLatency(size))
		rateLimiter:busyWait()
	end
	hist:print()
	hist:save("histogram.csv")
end

