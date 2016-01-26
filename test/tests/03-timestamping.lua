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

function slave(rxQueue, txQueue)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running()  do
		hist:update(timestamper:measureLatency())
	end
	hist:print()
	return 1
end
