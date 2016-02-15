-- Function to test: Timestamping
-- Test against: Network card support.

local luaunit 	= require "luaunit"
local dpdk	= require "dpdk"
local ts	= require "timestamping"
local hist	= require "histogram"
local device	= require "device"
local timer	= require "timer"

local log	= require "testlog"
local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE = 124

function master()
	log:info( "Function to test: Timestamping" )
	testlib:setRuntime( 10 )
	testlib:masterPairSingle()
end

function slave( rxDev , txDev )
	-- Init queues
	local rxQueue = rxDev:getRxQueue(0)
	local txQueue = txDev:getTxQueue(0)

	-- Init timestamper & histogram
	local timestamper = ts:newTimestamper( txQueue , rxQueue )
	local hist = hist:new()
	
	-- Init timer
	local runtime = timer:new( testlib.getRuntime() )
	
	-- Do timestamping
	while runtime:running() and dpdk.running()  do
		hist:update( timestamper:measureLatency() )
	end
	
	-- Get average, minimum & maximum latency
	local average = hist:avg()
	local minimum = hist:min()
	local maximum = hist:max()
	
	
	log:info( "Expecting maximum deviation: 64 ns" )
	log:info( "Recorded average deviation: " .. math.floor( average ) .. " ns" )
	
	log:info( "Maximum measured latency: " .. math.floor( maximum ) .. " ns")
	log:info( "Minimum measured latency: " .. math.floor( minimum ) .. " ns" )
	
	-- Check deviation
	if( ( maximum - average > 64 ) ) then
		log:warn( "Maximum latency of " .. maximum " ns exeeded 64 ns deviation from average " .. average .. " ns" )
	end
	if( ( average - minimum > 64 ) ) then
		log:warn( "Minimum latency of " .. minimum " ns exeeded 64 ns deviation from average " .. average .. " ns" )
		end
	
	-- Return result
	return ( maximum - average <= 64 ) and ( average - minimum <= 64 )
end
