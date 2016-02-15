local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local log	= require "testlog"
local testlib	= require "testlib"
local tconfig	= require "tconfig"

memory.enableCache()

local PKT_SIZE  = 124

function master()
	testlib:setRuntime( 2 )
	testlib:masterSingle()
end

function slave( dev , card )
	log:info( "Testing send capability." )
	local queue = dev:getTxQueue( 0 )
 
	local mem = memory.createMemPool( function( buf )
			buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = "10:11:12:13:14:15", --random src
				ethDst = "10:11:12:13:14:15", --random dst
			}
		end)
	
	local bufs = mem:bufArray(64)
	local i = 0
	local runtime = timer:new( testlib.getRuntime() )

	while dpdk.running() and runtime:running() do
		bufs:alloc( PKT_SIZE )
		queue:send( bufs )
		i = i + 64
	end
	
	-- Expected rate is ~ 99% of network card capability.
	local erate = math.floor( card[ 3 ] - math.min( 10 , card[ 3 ] * 99 / 100 ) )

	-- Measured rate equals packets * packet size / runtime.
	local mrate = math.floor( ( i * ( PKT_SIZE + 24 ) * 8 ) / ( 1000 * 1000 ) ) * 1 / testlib.getRuntime()
	
	log:info( "Expected rate: " .. erate .. " MBit/s" )

	if( erate >= mrate ) then
		log:warn( "Measured rate: " .. mrate .. " MBit/s | Missing: " .. erate - mrate .. " MBit/s" )
	else
		log:info( "Measured rate: " .. mrate .. " MBit/s" )
	end


	return erate < mrate
end
