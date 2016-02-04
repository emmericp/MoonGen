local dpdk	= require "dpdk"
local memory	= require "memory"
local ts	= require "timestamping"
local device	= require "device"
local filter	= require "filter"
local timer	= require "timer"
local stats	= require "stats"
local log	= require "log"

local tconfig	= require "tconfig"
local testlib	= require "testlib"

local FLOWS = 4
local RATE = 2000
local PKT_SIZE = 124

function master()
	testlib.masterMulti()
end

function slave1(...)
	return ...
end

--loadSlave
function slave2(rxDev, txDev)
	local counter = 0

	local mempool = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mempool:bufArray()

	local queue = txDev:getTxQueue( 0 )

	local txCtr = stats:newDevTxCounter(queue, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")

	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
	
	local mpps, tmbit = txCtr:getStats()
	local mpps, rmbit = rxCtr:getStats
	
	print(RATE)
	print(tmbit.avg)
	print(rmbit.avg)
	return (tmbit.avg - rmbit.avg <= RATE/100) and (tmbit.avg >= RATE) and (rmbit.avg >= RATE)
end