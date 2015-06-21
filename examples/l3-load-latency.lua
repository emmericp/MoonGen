local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local filter	= require "filter"
local hist		= require "histogram"
local stats		= require "stats"
local timer		= require "timer"
local arp		= require "proto.arp"

-- set addresses here
local DST_MAC	= nil -- resolved via ARP on GW_IP or DST_IP, can be overriden with a string here
local SRC_IP	= "10.0.0.10"
local DST_IP	= "10.1.0.10"
local SRC_PORT	= 1234
local DST_PORT	= 1234

-- answer ARP requests for this IP on the rx port
-- change this if benchmarking something like a NAT device
local RX_IP		= DST_IP
-- used to resolve DST_MAC
local GW_IP		= DST_IP

function master(...)
	local txPort, rxPort, rate, flows, size = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate [flows [pktSize]]]")
	end
	flows = flows or 4
	rate = rate or 2000
	size = (size or 124)
	txDev = device.config(txPort, 3, 3)
	rxDev = device.config(rxPort, 3, 3)
	device.waitForLinks()
	-- max 1mbit timestamping traffic timestamping
	-- rate will be somewhat off for high-latency links at low rates
	txDev:getTxQueue(0):setRate(rate - 1)
	dpdk.launchLua("loadSlave", txDev:getTxQueue(0), rxDev, size, flows)
	dpdk.launchLua("timerSlave", txDev:getTxQueue(1), rxDev:getRxQueue(1), size, flows)
	dpdk.launchLua(arp.arpTask, {
		-- run ARP on both ports
		{ rxQueue = rxDev:getRxQueue(2), txQueue = rxDev:getTxQueue(2), ips = RX_IP },
		{ rxQueue = txDev:getRxQueue(2), txQueue = txDev:getTxQueue(2), ips = SRC_IP }
	})
	dpdk.waitForSlaves()
end

local function fillUdpPacket(buf)
	buf:getUdpPacket():fill{
		ethSrc = queue,
		ethDst = DST_MAC,
		ip4Src = SRC_IP,
		ip4Dst = DST_IP,
		udpSrc = SRC_PORT,
		udpDst = DST_PORT
	}
end

local function doArp()
	if not DST_MAC then
		printf("Performing ARP lookup on %s", GW_IP)
		DST_MAC = arp.blockingLookup(GW_IP, 5)
		if not DST_MAC then
			printf("ARP lookup failed, using default destination mac address")
			return
		end
	end
	printf("Destination mac: %s", DST_MAC)
end

function loadSlave(queue, rxDev, size, flows)
	doArp()
	local mempool = memory.createMemPool(fillUdpPacket)
	local bufs = mempool:bufArray()
	local counter = 0
	local txCtr = stats:newDevTxCounter(queue, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")
	while dpdk.running() do
		bufs:alloc(size)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.udp:setSrcPort(SRC_PORT + counter)
			counter = incAndWrap(counter, flows)
		end
		-- UDP checksums are optional, so using just IPv4 checksums would be sufficient here
		bufs:offloadUdpChecksums()
		queue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
end

function timerSlave(txQueue, rxQueue, size, flows)
	doArp()
	rxQueue.dev:filterTimestamps(rxQueue)
	local timestamper = ts:newUdpTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	dpdk.sleepMillis(1000) -- ensure that the load task is running
	local counter = 0
	local rateLimit = timer:new(0.001)
	while dpdk.running() do
		hist:update(timestamper:measureLatency(size, function(buf)
			fillUdpPacket(buf)
			local pkt = buf:getUdpPacket()
			pkt.udp:setSrcPort(SRC_PORT + counter)
			counter = incAndWrap(counter, flows)
		end))
		rateLimit:wait()
		rateLimit:reset()
	end
	-- print the latency stats after all the other stuff
	dpdk.sleepMillis(300)
	hist:print()
	hist:save("histogram.csv")
end

