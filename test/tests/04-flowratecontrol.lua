-- Function to test: Flow rate control
-- Test against: Network card support.

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
	log:info( "Function to test: Flow Rate Control" )
	testlib:setRuntime( 5 )
	testlib:masterPairSingle()
end

function slave( rxDev , txDev , rxInfo , txInfo )
	-- Init queue
	local queue = txDev:getTxQueue( 0 )
	
	-- Init memory & bufs
	local mempool = memory.createMemPool( function( buf )
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)
	local bufs = mempool:bufArray()
	
	-- Init counter & timer
	local txCtr = stats:newDevTxCounter( queue , "plain" )
	local rxCtr = stats:newDevRxCounter( rxDev , "plain" )
	local runtime = timer:new( testlib.getRuntime() )

	-- Init & calculate rate
	local pass = true
	for x = 1 , 3 do
		local rate = rxInfo[ 3 ] * x / 4
		queue:setRate( rate  )
		log:info( "Expected rate: " .. math.floor( rate )  .. " MBit/s" )
	
		-- Do flow rate control
		while dpdk.running() and runtime:running() do
			bufs:alloc( PKT_SIZE )
			queue:send( bufs )
			txCtr:update()
			rxCtr:update()
		end
	
		-- Finalize counter & get stats
		txCtr:finalize()
		rxCtr:finalize()
		local y , tmbit = txCtr:getStats()
		local y , rmbit = rxCtr:getStats()
		
		-- Check measured rates
		local rPass = true
		if not ( tmbit.avg * 1.1 >= rate ) then
			log:warn( "Device sent: " .. tmbit.avg .. " MBit/s | Missing: " .. rate - tmbit.avg .. " MBit/s" )
			rPass = false
		else
			log:info( "Device sent: " .. math.floor( tmbit.avg ) .. " MBit/s")
		end
		if not ( rmbit.avg * 1.1 >= rate ) then
			log:warn( "Device received: " .. rmbit.avg .. " MBit/s | Missing: " .. rate - rmbit.avg .. " MBit/s" )
			rPass = false
		else
			log:info( "Device received: " .. math.floor( rmbit.avg ) .. " MBit/s")
		end
		if not rPass then
			log:warn( "Rate " .. ( rate ) .. " MBit/s failed!" )
		end
		pass = pass and rPass
		
	end
	
	-- Return result
	return pass
end
