EXPORT_ASSERTS_TO_GLOBALS = true

local luaunit 	= require "luaunit"
local dpdk	= require "dpdk"
local ts	= require "timestamping"
local hist	= require "histogram"
local device	= require "device"
local timer	= require "timer"
local tconfig 	= require "tconfig"

local PKT_SIZE = 124

Tests = {}

function master()
	local cards = tconfig.cards()
	local pairs = tconfig.pairs()

	local devs = {}
	for i=1, #pairs, 2 do
		devs[i] = device.config{ port = cards[pairs[i][1]+1][1], rxQueues = 2, txQueues = 3}
		devs[i+1] = device.config{ port = cards[pairs[i][2]+1][1], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()
	
	for i=1, #devs, 2 do
		slave(devs[i+1]:getRxQueue(0), devs[i]:getTxQueue(0))
		slave(devs[i]:getRxQueue(0), devs[i+1]:getTxQueue(0))
	end
	os.exit(luaunit.LuaUnit.run())
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
