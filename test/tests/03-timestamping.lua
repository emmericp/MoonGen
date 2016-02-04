EXPORT_ASSERTS_TO_GLOBALS = true

local luaunit 	= require "luaunit"
local dpdk	= require "dpdk"
local ts	= require "timestamping"
local hist	= require "histogram"
local device	= require "device"
local timer	= require "timer"
local log	= require "log"

local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE = 124

function master()
	testlib.masterMulti()
end

function slave1(...)
	return ...
end

function slave2(rxDev, txDev)
	local rxQueue = rxDev:getRxQueue(0)
	local txQueue = txDev:getTxQueue(0)

	log:info("Testing Timestamping.")	

	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running()  do
		hist:update(timestamper:measureLatency())
	end
	
	log:info("Expecting not more than 64ns deviation from average.")
	local average = hist:avg()
	log:info("Recorded average: " .. average)
	local min = average
	local max = average
	
	samples = hist.sortedHisto
	print(samples)
	log:info("Samples: " .. #samples)
	
	--for k,v in ipairs(samples) do
	--	for y,x in ipairs(v) do
	--		print(x) 
	--		if (x < min) then
	--			min = x
	--		end
	--		if (x > max) then
	--			max = x
	--		end	
	--	end
	--end
	log:info("Maximum time: " .. max)
	log:info("Minimum time: " .. min)
	if((max - average > 64) or (average - min > 64)) then
		log:warn("Deviation too large!")
	end
	
	return (max - average <= 64) and (average - min <= 64)
end
