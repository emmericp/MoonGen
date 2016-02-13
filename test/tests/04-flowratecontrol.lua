local dpdk	= require "dpdk"
local memory	= require "memory"
local ts	= require "timestamping"
local device	= require "device"
local filter	= require "filter"
local timer	= require "timer"
local stats	= require "stats"

local log	= require "testlog"
local tconfig	= require "tconfig"
local testlib	= require "testlib"

local FLOWS = 4
local RATE = 350
local PKT_SIZE = 124

function master()
	testlib:setRuntime( 5 )
	testlib:masterPairSingle()
end

function slave( rxDev , txDev , rxInfo , txInfo )
	local counter = 0

	local mempool = memory.createMemPool( function( buf )
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mempool:bufArray()

	local queue = txDev:getTxQueue( 0 )

	local maxrate = math.min ( RATE , rxInfo[ 3 ] )
	RATE = math.floor( math.random( maxrate / 10 , maxrate ) )
	queue:setRate( RATE )

	local txCtr = stats:newDevTxCounter( queue , "plain" )
	local rxCtr = stats:newDevRxCounter( rxDev , "plain" )

	local runtime = timer:new( testlib.getRuntime() )

	while dpdk.running() and runtime:running() do
		bufs:alloc( PKT_SIZE )
		queue:send( bufs )
		txCtr:update()
		rxCtr:update()
	end

	txCtr:finalize()
	rxCtr:finalize()
	
	local y , tmbit = txCtr:getStats()
	local y , rmbit = rxCtr:getStats()
	
	log:info( "Chosen rate: " .. RATE .. " MBit/s" )
	log:info( "Device sent with: " .. tmbit.avg .. " MBit/s (Average)" )
	log:info( "Device received: " .. rmbit.avg .. " MBit/s (Average)" )
	return ( tmbit.avg - rmbit.avg <= RATE / 100 ) and ( tmbit.avg >= RATE ) and ( rmbit.avg >= RATE )
end
