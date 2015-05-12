--- This script can be used to measure timestamping precision and accuracy.
--  Connect cables of different length between two ports (or a fiber loopback cable on a single port) to use this.
local dpdk		= require "dpdk"
local ts		= require "timestamping"
local device	= require "device"
local hist		= require "histogram"

function master(txPort, rxPort)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort")
	end
	local txDev = device.config(txPort)
	local rxDev = device.config(rxPort)
	device.waitForLinks()
	runTest(txDev:getTxQueue(0), rxDev:getRxQueue(0))
end

function runTest(txQueue, rxQueue)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	while dpdk.running() do
		hist:update(timestamper:measureLatency())
	end
	hist:print()
end

