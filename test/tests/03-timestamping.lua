EXPORT_ASSERTS_TO_GLOBALS = true

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
	testlib:setRuntime( 10 )
	testlib:masterPairSingle()
end

function slave( rxDev , txDev )
	local rxQueue = rxDev:getRxQueue(0)
	local txQueue = txDev:getTxQueue(0)

	log:info( "Testing Timestamping." )

	local timestamper = ts:newTimestamper( txQueue , rxQueue )
	local hist = hist:new()
	local runtime = timer:new( testlib.getRuntime() )
	while runtime:running() and dpdk.running()  do
		hist:update( timestamper:measureLatency() )
	end
	
	log:info( "Expecting not more than 64ns deviation from average." )
	local average = hist:avg()
	log:info( "Recorded average: " .. average )
	local minimum = hist:min()
	local maximum = hist:max()
	
	log:info( "Maximum time: " .. maximum )
	log:info( "Minimum time: " .. minimum )
	if( ( maximum - average > 64 ) or ( average - minimum > 64 ) ) then
		log:warn( "Deviation too large!" )
	end
	
	return ( maximum - average <= 64 ) and ( average - minimum <= 64 )
end
