EXPORT_ASSERTS_TO_GLOBALS = true

local luaunit 	= require "luaunit"
local dpdk	= require "dpdk"
local ts	= require "timestamping"
local hist	= require "histogram"
local device	= require "device"
local timer	= require "timer"

local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE = 124

function master()
	testlib.masterMulti()
end

function slave1(txQueue)
	return txQueue
end

function slave2(rxQueue, txQueue)
	print("[INFO] Testing timestamping.")
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running()  do
		hist:update(timestamper:measureLatency())
	end

	print("[INFO] Expected standard deviation: < 24.0")
	print("[INFO] Recorded standard deviation: " .. hist:standardDeviation())
	return hist:standardDeviation() < 24.0
end
