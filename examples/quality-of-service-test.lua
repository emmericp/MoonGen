--- This script implements a simple QoS test by generating two flows and measuring their latencies.
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local filter	= require "filter"
local stats		= require "stats"
local hist		= require "histogram"

local PKT_SIZE	= 124 -- without CRC
local ETH_DST	= "10:11:12:13:14:15" -- src mac is taken from the NIC
local IP_SRC	= "192.168.0.1"
local NUM_FLOWS	= 256 -- src ip will be IP_SRC + random(0, NUM_FLOWS - 1)
local IP_DST	= "10.0.0.1"
local PORT_SRC	= 1234
local PORT_FG	= 42
local PORT_BG	= 43

function master(txPort, rxPort, bgRate, fgRate)
	if not txPort or not rxPort then
		return print("usage: txPort rxPort [bgRate [fgRate]]")
	end
	fgRate = fgRate or 100
	bgRate = bgRate or 1500
	-- 3 tx queues: traffic, background traffic, and timestamped packets
	-- 2 rx queues: traffic and timestamped packets
	local txDev, rxDev
	-- these two cases could actually be merged as re-configurations of ports are ignored
	-- the dual-port case could just config the 'first' device with 2/3 queues
	-- however, this example scripts shows the explicit configuration instead of implicit magic
	if txPort == rxPort then
		-- sending and receiving from the same port
		txDev = device.config(txPort, 2, 3)
		rxDev = txDev
	else
		-- two different ports, different configuration
		txDev = device.config(txPort, 1, 3)
		rxDev = device.config(rxPort, 2)
	end
	-- wait until the links are up
	device.waitForLinks()
	printf("Sending %d MBit/s background traffic to UDP port %d", bgRate, PORT_BG)
	printf("Sending %d MBit/s foreground traffic to UDP port %d", fgRate, PORT_FG)
	-- setup rate limiters for CBR traffic
	-- see l2-poisson.lua for an example with different traffic patterns
	txDev:getTxQueue(0):setRate(bgRate)
	txDev:getTxQueue(1):setRate(fgRate)
	-- background traffic
	dpdk.launchLua("loadSlave", txDev:getTxQueue(0), PORT_BG)
	-- high priority traffic (different UDP port)
	dpdk.launchLua("loadSlave", txDev:getTxQueue(1), PORT_FG)
	-- count the incoming packets
	dpdk.launchLua("counterSlave", rxDev:getRxQueue(0))
	-- measure latency from a second queue
	timerSlave(txDev:getTxQueue(2), rxDev:getRxQueue(1), PORT_BG, PORT_FG, fgRate / (fgRate + bgRate))
	-- wait until all tasks are finished
	dpdk.waitForSlaves()
end

function loadSlave(queue, port)
	dpdk.sleepMillis(100) -- wait a few milliseconds to ensure that the rx thread is running
	-- TODO: implement barriers
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = PKT_SIZE, -- this sets all length headers fields in all used protocols
			ethSrc = queue, -- get the src mac from the device
			ethDst = ETH_DST,
			-- ipSrc will be set later as it varies
			ip4Dst = IP_DST,
			udpSrc = PORT_SRC,
			udpDst = port,
			-- payload will be initialized to 0x00 as new memory pools are initially empty
		}
	end)
	-- TODO: fix per-queue stats counters to use the statistics registers here
	local txCtr = stats:newManualTxCounter("Port " .. port, "plain")
	local baseIP = parseIPAddress(IP_SRC)
	-- a buf array is essentially a very thing wrapper around a rte_mbuf*[], i.e. an array of pointers to packet buffers
	local bufs = mem:bufArray()
	while dpdk.running() do
		-- allocate buffers from the mem pool and store them in this array
		bufs:alloc(PKT_SIZE)
		for _, buf in ipairs(bufs) do
			-- modify some fields here
			local pkt = buf:getUdpPacket()
			-- select a randomized source IP address
			-- you can also use a wrapping counter instead of random
			pkt.ip4.src:set(baseIP + math.random(NUM_FLOWS) - 1)
			-- you can modify other fields here (e.g. different source ports or destination addresses)
		end
		-- send packets
		bufs:offloadUdpChecksums()
		txCtr:updateWithSize(queue:send(bufs), PKT_SIZE)
	end
	txCtr:finalize()
end

function counterSlave(queue)
	-- the simplest way to count packets is by receiving them all
	-- an alternative would be using flow director to filter packets by port and use the queue statistics
	-- however, the current implementation is limited to filtering timestamp packets
	-- (changing this wouldn't be too complicated, have a look at filter.lua if you want to implement this)
	-- however, queue statistics are also not yet implemented and the DPDK abstraction is somewhat annoying
	local bufs = memory.bufArray()
	local ctrs = {}
	while dpdk.running(100) do
		local rx = queue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getUdpPacket()
			local port = pkt.udp:getDstPort()
			local ctr = ctrs[port]
			if not ctr then
				ctr = stats:newPktRxCounter("Port " .. port, "plain")
				ctrs[port] = ctr
			end
			ctr:countPacket(buf)
		end
		-- update() on rxPktCounters must be called to print statistics periodically
		-- this is not done in countPacket() for performance reasons (needs to check timestamps)
		for k, v in pairs(ctrs) do
			v:update()
		end
		bufs:freeAll()
	end
	for k, v in pairs(ctrs) do
		v:finalize()
	end
	-- TODO: check the queue's overflow counter to detect lost packets
end

-- TODO: move this function into the timestamping library
local function measureLatency(txQueue, rxQueue, bufs, rxBufs)
	ts.syncClocks(txQueue.dev, rxQueue.dev)
	txQueue:send(bufs)
	-- increment the wait time when using large packets or slower links
	local tx = txQueue:getTimestamp(100)
	if tx then
		dpdk.sleepMicros(500) -- minimum latency to limit the packet rate
		-- sent was successful, try to get the packet back (max. 10 ms wait time before we assume the packet is lost)
		local rx = rxQueue:tryRecv(rxBufs, 10000)
		if rx > 0 then
			local numPkts = 0
			for i = 1, rx do
				if bit.bor(rxBufs[i].ol_flags, dpdk.PKT_RX_IEEE1588_TMST) ~= 0 then
					numPkts = numPkts + 1
				end
			end
			local delay = (rxQueue:getTimestamp() - tx) * 6.4
			if numPkts == 1 then
				if delay > 0 and delay < 100000000 then
					rxBufs:freeAll()
					return delay
				end
			end -- else: got more than one packet, so we got a problem
			rxBufs:freeAll()
		end
	end
end

-- TODO refactor this to use the new API
function timerSlave(txQueue, rxQueue, bgPort, port, ratio)
	local txDev = txQueue.dev
	local rxDev = rxQueue.dev
	local mem = memory.createMemPool()
	local bufs = mem:bufArray(1)
	local rxBufs = mem:bufArray(128)
	txQueue:enableTimestamps()
	rxDev:filterTimestamps(rxQueue)
	local histBg, histFg = hist(), hist()
	-- wait one second, otherwise we might start timestamping before the load is applied
	dpdk.sleepMillis(1000)
	local counter = 0
	local baseIP = parseIPAddress(IP_SRC)
	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		local pkt = bufs[1]:getUdpPacket()
		local port = math.random() <= ratio and port or bgPort
		-- TODO: ts.fillPacket must be fixed
		ts.fillPacket(bufs[1], port, PKT_SIZE + 4)
		pkt:fill{
			pktLength = PKT_SIZE, -- this sets all length headers fields in all used protocols
			ethSrc = txQueue, -- get the src mac from the device
			ethDst = ETH_DST,
			-- ipSrc will be set later as it varies
			ip4Dst = IP_DST,
			udpSrc = PORT_SRC,
			udpDst = port,
			-- payload will be initialized to 0x00 as new memory pools are initially empty
		}
		pkt.ip4.src:set(baseIP + math.random(NUM_FLOWS) - 1)
		bufs:offloadUdpChecksums()
		rxQueue:enableTimestamps(port)
		local lat = measureLatency(txQueue, rxQueue, bufs, rxBufs)
		if lat then
			local hist = port == bgPort and histBg or histFg
			hist:update(lat)
		end
	end
	dpdk.sleepMillis(100) -- to prevent overlapping stdout
	histBg:save("hist-background.csv")
	histFg:save("hist-foreground.csv")
	histBg:print("Background traffic")
	histFg:print("Foreground traffic")
end

