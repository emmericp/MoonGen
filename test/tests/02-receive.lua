local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE	= 100

function master()
	testlib.masterMulti()
end

function slave1(txQueue)
	dpdk.sleepMillis(100)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mem:bufArray(1)

	local i = 0
	local max = 100
	local runtime = timer:new(1)
	while dpdk.running() and runtime:running() and i < max do
		bufs:alloc(PKT_SIZE)
		txQueue:send(bufs)
		i = i + 1
	end
	return i
end

function slave2(rxQueue, sent)
	dpdk.sleepMillis(100)
	local bufs = memory.bufArray()
	runtime = timer:new(1)
	local packets = 0
	while runtime:running() and dpdk.running() do
		maxWait = 1
		local rx = rxQueue:tryRecv(bufs, maxWait)
		for i=1, rx do
			packets = packets + 1
		end
		bufs:free(rx)
	end
	return packets >= sent
end
