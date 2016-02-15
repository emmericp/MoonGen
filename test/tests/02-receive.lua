-- Function to test: Receive
-- Test against: Sending network card rate.

local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"
local stats 	= require "stats"

local log	= require "testlog"
local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE	= 124

function master()
	log:info( "Function to test: Receive" )
	testlib:setRuntime( 10 )
	testlib:masterPairMulti()
end

function slave1( txDev, rxDev )
	-- Init queue
	local txQueue = txDev:getTxQueue( 0 )

	-- Init memory & bufs
	local mem = memory.createMemPool( function( buf )
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "10:11:12:13:14:15"
		}
	end)
	local bufs = mem:bufArray()
	
	-- Init counter & timer
	local ctr = stats:newDevTxCounter( txDev , "plain" )
	local runtime = timer:new( testlib.getRuntime() )

	-- Send packets
	while dpdk.running() and runtime:running() do
		bufs:alloc( PKT_SIZE )
		txQueue:send( bufs )
		ctr:update()
	end
	
	-- Finalize counter and get stats
	ctr:finalize()
	local x , mbit = ctr:getStats()

	-- Return measured rate
	return mbit.avg
end

function slave2( txDev , rxDev )
	-- Init queue
	local queue = rxDev:getRxQueue( 0 )
	
	-- Init bufs
	local bufs = memory.bufArray()
	
	-- Init counter & timer
	local ctr = stats:newManualRxCounter(queue.dev, "plain")
	local runtime = timer:new(10)
	
	-- Receive packets
	while runtime:running() and dpdk.running() do
		local rx = queue:tryRecv(bufs, 10)
		bufs:freeAll()
		ctr:updateWithSize(rx, PKT_SIZE)
	end
	
	-- Finalize counter and get stats
	ctr:finalize()
	local x , mbit = ctr:getStats()

	-- Return measured rate
	return mbit.avg
end

-- Compare measured rates
function compare( sRate , rRate )	
	-- Round receive rate down
	return2 = math.floor( rRate )
	
	-- Round max rate down | substract 10 MBit/s (max. 1% of rate).
	srate = math.floor( math.min( sRate - 10 , sRate * 99 / 100 ) )
	
	-- Compare rates
	log:info( "Expected receive rate: " .. math.floor( sRate ) .. " MBit/s" )
	if ( sRate > rRate ) then
		log:warn( "Measured receive rate: " .. rRate .. " MBit/s | Missing: " .. sRate - rRate .. " MBit/s")
	else
		log:info( "Measured receive rate: " .. math.floor( sRate ) .. " MBit/s")
	end

	-- Return result
	return sRate <= rRate
end
