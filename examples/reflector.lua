-- vim:ts=4:sw=4:noexpandtab
--- Layer 2 echo server
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local lacp		= require "proto.lacp"

function master(...)
	if select("#", ...) < 1 then
		return print("usage: port [ports...]")
	end
	local ports = { ... }
	local lacpQueues = {}
	for i = 1, select("#", ...) do
		local port = device.config{port = ports[i], rxQueues = 2, txQueues = 2}
		lacpQueues[#lacpQueues + 1] = { rx = port:getRxQueue(1), tx = port:getTxQueue(1) }
		ports[i] = port
	end
	device.waitForLinks()
	dpdk.launchLua(lacp.lacpTask, { name = "bond0", ports = lacpQueues})
	dpdk.sleepMillis(100) -- setup lacp passively
	--lacp.waitForLink("bond0")
	for i, port in ipairs(ports) do 
		local rxQ = port:getRxQueue(0)
		local txQ = port:getTxQueue(0)
		dpdk.launchLua("reflectorSlave", rxQ, txQ)
	end
	dpdk.waitForSlaves()
end

function reflectorSlave(rxQ, txQ)
	local bufs = memory.bufArray()
	local txCtr = stats:newDevTxCounter(txQ.dev, "plain")
	local rxCtr = stats:newDevRxCounter(rxQ.dev, "plain")
	while dpdk.running() do
		local rx = rxQ:tryRecv(bufs, 1000)
		for i = 1, rx do
			-- swap MAC addresses
			local pkt = bufs[i]:getEthernetPacket()
			local tmp = pkt.eth:getDst()
			pkt.eth:setDst(pkt.eth:getSrc())
			pkt.eth:setSrc(tmp)
			local vlan = bufs[i]:getVlan()
			if vlan then
				bufs[i]:setVlan(vlan)
			end
		end
		txQ:sendN(bufs, rx)
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
end

