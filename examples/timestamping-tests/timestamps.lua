--- This script can be used to measure timestamping precision and accuracy.
--  Connect cables of different length between two ports (or a fiber loopback cable on a single port) to use this.
local mg		= require "dpdk"
local ts		= require "timestamping"
local device	= require "device"
local hist		= require "histogram"
local memory	= require "memory"
local stats		= require "stats"

local PKT_SIZE = 128

function master(txPort, rxPort, load)
	if not txPort or not rxPort or load and type(load) ~= "number" then
		errorf("usage: txPort rxPort [load]")
	end
	local txDev = device.config({port = txPort, rxQueues = 2, txQueues = 2})
	local rxDev = device.config({port = rxPort, rxQueues = 2, txQueues = 2})
	device.waitForLinks()
	if load then
		-- set the wire rate and not the payload rate
		load = load * PKT_SIZE / (PKT_SIZE + 24)
		txDev:getTxQueue(0):setRate(load)
		mg.launchLua("loadSlave", txDev:getTxQueue(0), true)
		mg.sleepMillis(500)
	end
	runTest(txDev:getTxQueue(1), rxDev:getRxQueue(1))
end

function loadSlave(queue, showStats)
	local mem = memory.createMemPool(function(buf)
		buf:getEthPacket():fill{
		}
	end)
	bufs = mem:bufArray()
	local ctr = stats:newDevTxCounter(queue.dev, "plain")
	while mg.running() do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		if showStats then ctr:update() end
	end
	if showStats then ctr:finalize() end
end

function runTest(txQueue, rxQueue)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	while mg.running() do
		hist:update(timestamper:measureLatency())
	end
	hist:save("histogram.csv")
	hist:print()
end

