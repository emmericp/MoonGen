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
	local devs = {}
	for i=1, #cards do
		devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()
	
	for i=1, #cards do
		Tests["testNic" .. cards[i][1]] = function()
			luaunit.assertTrue(slave(devs[i]:getTxQueue(0), devs[i]:getRxQueue(0)))
		end
	end
	os.exit(luaunit.LuaUnit.run())
end

function slave(txQueue, rxQueue)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running()  do
		hist:update(timestamper:measureLatency())
	end
	hist:print()
	return 1
end
