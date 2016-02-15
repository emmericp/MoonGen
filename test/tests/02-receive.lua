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
	testlib:setRuntime( 10 )
	testlib:masterPairMulti()
end

function slave1( txDev, rxDev )
	local txQueue = txDev:getTxQueue( 0 )
	local txCtr = stats:newDevTxCounter( txDev , "plain" )

	local mem = memory.createMemPool( function( buf )
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "10:11:12:13:14:15"
		}
	end)

	local bufs = mem:bufArray()
	local runtime = timer:new( testlib.getRuntime() )

	while dpdk.running() and runtime:running() do
		bufs:alloc( PKT_SIZE )
		txQueue:send( bufs )
		txCtr:update()
	end
	txCtr:finalize()

	local y , mbit = txCtr:getStats()

	return mbit.avg
end

function slave2( txDev , rxDev )
	local queue = rxDev:getRxQueue( 0 )
	
	local bufs = memory.bufArray()
	local ctr = stats:newManualRxCounter(queue.dev, "plain")
	local runtime = timer:new(10)
	while runtime:running() and dpdk.running() do
		local rx = queue:tryRecv(bufs, 10)
		bufs:freeAll()
		ctr:updateWithSize(rx, PKT_SIZE)
	end
	
	local y , mbit = ctr:getStats()

	return mbit.avg
end

function compare( return1 , return2 )
	return2 = math.floor( return2 )
	return1 = math.floor( math.min( return1 - 10 , return1 * 99 / 100 ) )
	
	log:info( "Expected receive rate: " .. return1 .. " MBit/s" )

	if ( return1 > return2 ) then
		log:warn( "Measured receive rate: " .. return2 .. " MBit/s | Missing: " .. return1 - return2 .. " MBit/s")
	else
		log:info( "Measured receive rate: " .. return2 .. "MBit/s")
	end

	return return1 <= return2
end
