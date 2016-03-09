-- Function to test: Send
-- Test against: Network card speed.

local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local log	= require "testlog"
local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE  = 124

function master()
	log:info( "Function to test: Send" )
	testlib:setRuntime( 10 )
	testlib:masterSingle()
end

function slave( dev , card )
	
	-- Calculate expected rate | erate set to 10 MBit/s below max rate (max. 1% of rate)
	local eRate = card [ 3 ]
	eRate = math.floor( eRate - math.min( 10 , eRate * 99 / 100 ) )
	log:info( "Expected rate: " .. eRate .. " MBit/s" )
	
	-- Init queue
	local queue = dev:getTxQueue( 0 )
	
	-- Init memory & bufs
	local mem = memory.createMemPool( function( buf )
			buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = "10:11:12:13:14:15",
				ethDst = "10:11:12:13:14:15"
			}
		end)
	local bufs = mem:bufArray( 64 )
	
	-- Init counter & timer
	local i = 0
	local runtime = timer:new( testlib.getRuntime() )

	-- Send packets
	while dpdk.running() and runtime:running() do
		bufs:alloc( PKT_SIZE )
		queue:send( bufs )
		i = i + 64
	end

	-- Calculate measured rate | mrate equals packets * packet size / runtime
	local mRate = math.floor( ( i * ( PKT_SIZE + 24 ) * 8 ) / ( 1000 * 1000 ) ) * 1 / testlib.getRuntime()

	-- Check against erate
	if( eRate >= mRate ) then
		log:warn( "Measured rate: " .. mRate .. " MBit/s | Missing: " .. eRate - mRate .. " MBit/s" )
	else
		log:info( "Measured rate: " .. mRate .. " MBit/s" )
	end

	-- Return result
	return eRate < mRate
end
