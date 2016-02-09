local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"
local log	= require "log"

local testlib	= require "testlib"
local tconfig	= require "tconfig"

memory.enableCache()

local PKT_SIZE  = 124

function master()
	testlib.setRuntime( 10 )
	testlib.masterSingle()
end

function slave( dev , card )
	log:info( "Testing send capability." )
	log:info( "Expected rate: " .. card[ 3 ] .. " MBit/s" )
	local queue = dev:getTxQueue( 0 )
	dpdk.sleepMillis( 100 )
 
	local mem = memory.createMemPool( function( buf )
			buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = "10:11:12:13:14:15", --random src
				ethDst = "10:11:12:13:14:15", --random dst
			}
		end)
	
	local bufs = mem:bufArray( PKT_SIZE )
	local i = 0
	local runtime = timer:new( testlib.getRuntime() )

	while dpdk.running() and runtime:running() do
		bufs:alloc( PKT_SIZE )
		queue:send( bufs )
		i = i + 1
	end
	
	local rate = math.floor( ( i * ( PKT_SIZE + 64 ) ) / ( 1000 ) ) * 1 / testlib.getRuntime()
	log:info( "Measured rate: " .. rate .. " MBit/s (Average)" )
	if( card[ 3 ] >= rate ) then
		log:warn( "Network card is not operating at full capability." )
	end

	return card[ 3 ] < rate
end
