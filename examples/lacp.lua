-- vim:ts=4:sw=4:noexpandtab
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local stats		= require "stats"
local hist		= require "histogram"
local lacp		= require "proto.lacp"

local PKT_SIZE = 60
local ETH_DST = "ff:ff:ff:ff:ff:ff"

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
		local port = device.config{port = ports[i], rxQueues = 4, txQueues = 4} 
		lacpQueues[#lacpQueues + 1] = { rx = port:getRxQueue(1), tx = port:getTxQueue(1) }
		ports[i] = port
	end
	device.waitForLinks()
	dpdk.launchLua(lacp.lacpTask, { name = "bond0", ports = lacpQueues})
	lacp.waitForLink("bond0")
	for i, port in ipairs(ports) do 
		local queue = port:getTxQueue(0)
		queue:setRate(rate)
		dpdk.launchLua("loadSlave", queue)
	end
	--dpdk.launchLua("timerSlave", txDev:getTxQueue(0), rxDev:getRxQueue(1), histfile)
	dpdk.waitForSlaves()
end

function loadSlave(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = queue,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local txCtr = stats:newDevTxCounter(queue.dev, "plain")
	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		txCtr:update()
	end
	txCtr:finalize()
end

function timerSlave(txQueue, rxQueue, histfile)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	dpdk.sleepMillis(1000) -- ensure that the load task is running
	while dpdk.running() do
		hist:update(timestamper:measureLatency(function(buf) buf:getEthernetPacket().eth.dst:setString(ETH_DST) end))
	end
	hist:print()
	hist:save(histfile)
end

