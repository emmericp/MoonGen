-- vim:ts=4:sw=4:noexpandtab
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local stats		= require "stats"
local hist		= require "histogram"
local lacp		= require "proto.lacp"

local PKT_SIZE      = 60
local ETH_DST       = "90:E2:BA:C0:EE:8C"
local SRC_IP        = "10.10.10.1"
local DST_IP        = "10.10.10.2"
local SRC_PORT_BASE = 3000 -- + NIC id 
local DST_PORT_BASE = 4000 -- + count(NUM_FLOWS)
local NUM_FLOWS		= 100 -- per port

function master(...)
	if select("#", ...) < 2 then
		return print("usage: port [ports...] ratePerPort")
	end
	local rate = select(select("#", ...), ...)
	local ports = { ... }
	ports[#ports] = nil
	rate = rate or 10000
	local lacpQueues = {}
	for i = 1, select("#", ...) - 1 do
		local port = device.config{port = ports[i], rxQueues = 3, txQueues = 3} 
		lacpQueues[#lacpQueues + 1] = {rx = port:getRxQueue(1), tx = port:getTxQueue(1)}
		ports[i] = port
	end
	device.waitForLinks()
	dpdk.launchLua(lacp.lacpTask, {name = "bond0", ports = lacpQueues})
	lacp.waitForLink("bond0")
	for i, port in ipairs(ports) do 
		local queue = port:getTxQueue(0)
		queue:setRate(rate)
		dpdk.launchLua("loadSlave", queue)
	end
	dpdk.waitForSlaves()
end

function loadSlave(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			ethSrc = queue,
			ethDst = ETH_DST,
			ip4Src = SRC_IP,
			ip4Dst = DST_IP,
			udpSrc = SRC_PORT_BASE + queue.id,
			pktLength = PKT_SIZE
		}
	end)
	local bufs = mem:bufArray()
	local txCtr = stats:newDevTxCounter(queue.dev, "plain")
	local counter = 0
	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.udp:setDstPort(DST_PORT_BASE + counter)
			counter = incAndWrap(counter, NUM_FLOWS)
		end
		bufs:offloadUdpChecksums()
		--bufs:setVlans(1234)
		queue:send(bufs)
		txCtr:update()
	end
	txCtr:finalize()
end

