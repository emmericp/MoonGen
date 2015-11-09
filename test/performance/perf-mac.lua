local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"

local PKT_SIZE	= 60

function master(loadPort, dutPort)
	if not loadPort or not dutPort then
		return print("usage: loadPort dutPort")
	end
	local loadDev = device.config{ port = loadPort }
	local dutDev = device.config{ port = dutPort, mempool = memory.createMemPool{ n = 4095 } }
	device.waitForLinks()
	dpdk.launchLua("loadSlave", loadDev:getTxQueue(0), loadDev:getRxQueue(0))
	dpdk.launchLua("dutSlave", dutDev:getRxQueue(0), dutDev:getTxQueue(0))
	dpdk.waitForSlaves()
end


function loadSlave(txQueue, rxQueue)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket().eth:setSrcString("01:02:03:04:05:06")
		buf:getEthernetPacket().eth:setDstString("07:08:09:0A:0B:0C")
	end)
	local bufs = mem:bufArray()
	local rxBufs = memory.bufArray()
	local flow = 0
	local txCtr = stats:newDevTxCounter(txQueue, "plain")
	local rxCtr = stats:newDevRxCounter(rxQueue, "plain")
	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		txQueue:send(bufs)
		if math.random() > 0.99 then -- this task must never be the bottleneck, even on slow CPUs
			local rx = rxQueue:tryRecv(rxBufs, 10)
			for i = 1, rx do
				local buf = rxBufs[i]
				local pkt = buf:getRawPacket()
				if pkt.uint32[0] ~= 0x04030201
				or pkt.uint32[1] ~= 0x08070605
				or pkt.uint32[2] ~= 0x0C0B0A09
				or pkt.uint32[3] ~= 0 then -- must not touch any other bytes
					print("ERROR: received bad packet")
					buf:dump()
					return false
				end
			end
			rxBufs:freeAll()
		end
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
end

function dutSlave(rxQueue, txQueue)
	local bufs = memory.bufArray()
	while dpdk.running() do
		local rx = rxQueue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getEthernetPacket()
			local src = pkt.eth:getSrc()
			local dst = pkt.eth:getDst()
			pkt.eth:setSrc(dst)
			pkt.eth:setDst(src)
		end
		txQueue:sendN(bufs, rx)
	end
end

