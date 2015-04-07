local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local dpdkc		= require "dpdkc"
local filter	= require "filter"
local ffi		= require "ffi"

local incAndWrap = incAndWrap

-- set addresses here
local srcmac = "00:42:00:00:00:01"
local dstmac = "00:42:00:00:00:02"
local dstip = 0x0A000001
local srcip = 0x0A000002

function master(...)
	local txPort, rxPort, rate, flows, size = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate [flows [size]]]")
	end
	flows = flows or 4
	rate = rate or 2000
	size = (size or 128) - 4 -- 4 bytes for CRC will be added by NIC
	local rxMempool = memory.createMemPool()
	if txPort == rxPort then
		txDev = device.config(txPort, rxMempool, 2, 2)
		rxDev = txDev
		txDev:wait()
	else
		txDev = device.config(txPort, rxMempool, 1, 2)
		rxDev = device.config(rxPort, rxMempool, 2, 1)
		device.waitForLinks()
	end
	txDev:getTxQueue(1):setRate(rate)
	dpdk.launchLua("timerSlave", txPort, rxPort, 0, 1, size, flows)
	dpdk.launchLua("loadSlave", txPort, 1, size, flows)
	dpdk.launchLua("counterSlave", rxPort, size)
	dpdk.waitForSlaves()
end

function loadSlave(port, queue, size, numFlows)
	local queue = device.get(port):getTxQueue(queue)
	local mempool = memory.createMemPool(function(buf)
		-- TODO: port this to new PTP/timestamping functions, ffi.cast in a userscript is not the point
		ts.fillPacket(buf, 1234, size)
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		data[43] = 0x00 -- PTP version, set to 0 to disable timestamping for load packets
		local pkt = buf:getUdpPacket()
		pkt.eth.src:setString(srcmac)
		pkt.eth.dst:setString(dstmac)
		pkt.ip.dst:set(dstip)
	end)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mempool:bufArray(128)
	local baseIP = srcip
	local counter = 0
	while dpdk.running() do
		bufs:alloc(size)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip.src:set(baseIP + counter)
			counter = incAndWrap(counter, numFlows)
		end
		-- UDP checksums are optional, so using just IPv4 checksums would be sufficient here
		bufs:offloadUdpChecksums()
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * (size + 4) * 8, mpps * (size + 24) * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function counterSlave(port)
	local dev = device.get(port)
	local total = 0
	while dpdk.running() do
		local time = dpdk.getTime()
		dpdk.sleepMillis(1000)
		local elapsed = dpdk.getTime() - time
		local pkts = dev:getRxStats(port)
		total = total + pkts
		printf("Received %d packets, current rate %.2f Mpps", total, pkts / elapsed / 10^6)
	end
	printf("Received %d packets", total)
end

function timerSlave(txPort, rxPort, txQueue, rxQueue, size, numFlows)
	local txDev = device.get(txPort)
	local rxDev = device.get(rxPort)
	local txQueue = txDev:getTxQueue(txQueue)
	local rxQueue = rxDev:getRxQueue(rxQueue)
	local mem = memory.createMemPool()
	local bufs = mem:bufArray(1)
	local rxBufs = mem:bufArray(128)
	txQueue:enableTimestamps()
	rxQueue:enableTimestamps(1234)
	rxDev:filterTimestamps(rxQueue)
	local hist = {}
	-- wait one second, otherwise we might start timestamping before the load is applied
	dpdk.sleepMillis(1000)
	local counter = 0
	local baseIP = dstip
	while dpdk.running() do
		bufs:alloc(size + 4)
		local pkt = bufs[1]:getUdpPacket()
		ts.fillPacket(bufs[1], 1234, size)
		pkt.eth.src:setString(srcmac)
		pkt.eth.dst:setString(dstmac)
		pkt.ip.src:set(baseIP + counter)
		pkt.ip.dst:set(dstip)
		counter = (counter + 1) % numFlows
		bufs:offloadUdpChecksums()
		-- sync clocks and send
		ts.syncClocks(txDev, rxDev)
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
						hist[delay] = (hist[delay] or 0) + 1
					end
				end -- else: got more than one packet, so we got a problem
				-- TODO: use sequence numbers in the packets to avoid bugs here
				rxBufs:freeAll()
			end
		end
	end
	local sortedHist = {}
	for k, v in pairs(hist) do 
		table.insert(sortedHist,  { k = k, v = v })
	end
	local sum = 0
	local samples = 0
	table.sort(sortedHist, function(e1, e2) return e1.k < e2.k end)
	print("Histogram:")
	for _, v in ipairs(sortedHist) do
		sum = sum + v.k * v.v
		samples = samples + v.v
		print(v.k, v.v)
	end
	print()
	print("Average: " .. (sum / samples) .. " ns, " .. samples .. " samples")
	print("----------------------------------------------")
end

