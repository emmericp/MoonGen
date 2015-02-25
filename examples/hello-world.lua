--- This script implements a simple QoS test by generating two flows and measuring their latencies.
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local filter	= require "filter"

local PKT_SIZE = 124

function master(txPort, rxPort, rate, bgRate)
	if not txPort or not rxPort then
		return print("usage: txPort rxPort [rate [bgRate]]")
	end
	rate = rate or 100
	bgRate = bgRate or 1500
	-- 3 tx queues: traffic, background traffic, and timestamped packets
	local txDev = device.config(txPort, 1, 3)
	-- 2 rx queues: traffic and timestamped packets
	local rxDev = device.config(rxPort, 2)
	-- wait until the link is up
	device.waitForLinks()
	-- setup rate limiters for CBR traffic
	-- see l2-poisson.lua for an example with different traffic patterns
	txDev:getTxQueue(0):setRate(bgRate)
	txDev:getTxQueue(1):setRate(rate)
	-- background traffic
	dpdk.launchLua("loadSlave", txDev:getTxQueue(0), 42)
	-- high priority traffic (different UDP port)
	dpdk.launchLua("loadSlave", txDev:getTxQueue(1), 43)
	-- count the incoming packets
	dpdk.launchLua("counterSlave", rxDev:getRxQueue(0), 42, 43)
	-- measure latency from a second queue
	dpdk.launchLua("timerSlave", txDev:getTxQueue(2), rxDev:getRxQueue(1), 42, 43, rate / bgRate)
	-- wait until all tasks are finished
	dpdk.waitForSlaves()
end

function loadSlave(queue, port, rate)
	dpdk.sleepMillis(100) -- wait a few milliseconds to ensure that the rx thread is running
	-- TODO: implement barriers
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = PKT_SIZE, -- this sets all length headers fields in all used protocols
			ethSrc = queue, -- get the src mac from the device
			ethDst = "10:11:12:13:14:15",
			-- ipSrc will be set later as it varies
			ipDst = "192.168.1.1",
			udpSrc = 1234,
			udpDst = port,
			-- payload will be initialized to 0x00 as new memory pools are initially empty
		}
	end)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local totalReceived = 0
	local baseIP = parseIPAddress("10.0.0.1")
	-- a buf array is essentially a very thing wrapper around a rte_mbuf*[], i.e. an array of pointers to packet buffers
	local bufs = mem:bufArray()
	while dpdk.running() do
		-- allocate buffers from the mem pool and store them in this array
		bufs:fill(PKT_SIZE)
		for _, buf in ipairs(bufs) do
			-- modify some fields here
			local pkt = buf:getUdpPacket()
			-- select a randomized source IP address
			-- you can also use a wrapping counter instead of random
			pkt.ip.src:set(baseIP + math.random() * 255)
			-- you can modify other fields here (e.g. different source ports or destination addresses)
		end
		-- send packets
		totalSent = totalSent + queue:send(bufs)
		-- print statistics
		-- TODO: this should be in a utility function
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			--local rx = dev:getRxStats(port)
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("%s Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", queue, totalSent, mpps, mpps * (PKT_SIZE + 4) * 8, mpps * (PKT_SIZE + 24) * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function counterSlave(queue)
	-- the simplest way to count packets is by receiving them all
	-- an alternative would be using flow director to filter packets by port and use the queue statistics
	-- however, the current implementation is limited to filtering timestamp packets
	-- (changing this wouldn't be too complicated, have a look at filter.lua if you want to implement this)
	local bufs = memory.bufArray()
	local stats = {}
	local lastPrint = 0
	local lastStats = {}
	while dpdk.running() do
		local rx = queue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getUdpPacket()
			local port = pkt.udp.dst
			stats[port] = (stats[port] or 0) + 1
		end
		bufs:freeAll()
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			for k, v in pairs(stats) do
				local last = lastStats[k] or 0
				local mpps = (v - last) / (time - lastPrint) / 10^6
				printf("%s Port %d: Received %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", queue, k, v, mpps, mpps * (PKT_SIZE + 4) * 8, mpps * (PKT_SIZE + 24) * 8)
				lastStats[k] = v
			end
			lastPrint = time
		end
	end
	-- TODO: check the queue's overflow counter to detect lost packets
end

function timerSlave(...)
	-- TODO add latency (probably when the simplified TS API is finished)
end

