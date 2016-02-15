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
	local pass = true

	local rate = rxInfo[ 3 ]
	for x = 1 , 3 do
		queue:setRate( rate * x / 4 )

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
	
		log:info( "Chosen rate: " .. ( rate * x / 4 )  .. " MBit/s" )
		log:info( "Device sent with: " .. tmbit.avg .. " MBit/s (Average)" )
		log:info( "Device received: " .. rmbit.avg .. " MBit/s (Average)" )

		pass = pass and ( tmbit.avg - rmbit.avg <= rate * x / 190 ) and ( tmbit.avg * 1.1 >= rate * x / 4 ) and ( rmbit.avg * 1.1 >= rate * x / 4 )
		if not pass then
			log:warn( "Rate " .. ( rate * x / 4 ) .. " MBit/s failed!" )
		end
	end
	return pass
end
