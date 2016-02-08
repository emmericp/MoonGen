local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local log	= require "log"
local timer	= require "timer"

local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE	= 124

function master()
	testlib.setRuntime(0.1)
	testlib.masterPairMulti()
end

function slave1(txDev, rxDev)
	local txQueue = txDev:getTxQueue(0)
	dpdk.sleepMillis(100)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mem:bufArray(1)

	local runtime = timer:new(testlib.getRuntime())
	local i = 0

	while dpdk.running() and runtime:running() do
		bufs:alloc(PKT_SIZE)
		txQueue:send(bufs)
		i = i + 1
	end
	return i
end

function slave2(rxDev, txDev, sent)
	local rxQueue = rxDev:getRxQueue(0)
	log:info("Testing receive capability.")

	dpdk.sleepMillis(100)
	local bufs = memory.bufArray()
	local packets = 0
	local runtime = timer:new(testlib.getRuntime())
	while dpdk.running() and runtime:running() do
		maxWait = 1
		local rx = rxQueue:tryRecv(bufs, maxWait)
		for i=1, rx do
			packets = packets + 1
		end
		bufs:free(rx)
	end

	log:info("Packets to receive: " .. sent)
	log:info("Packets received: " .. packets)
	if(packets < sent) then
		log:warn("Network card did not receive all packages!")
	end
	return packets >= sent
end
