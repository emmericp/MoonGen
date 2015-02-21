local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"
local utils	= require "utils"

local ffi	= require "ffi"

function master(...)
	local portA, portB, rate = tonumberall(...)
	if not portA or not portB then
		errorf("usage: txPort rxPort [rate]")
	end
	if not portA == portB then
		errorf("use different ports")
	end
	rate = rate or 10000
	local rcWorkaround = rate > (64 * 64) / (84 * 84) * 10000 and rate < 10000
	local devA, devB
	-- Ab gewisser größe muss über mehrere queues verschickt werden
	local txQueueCount = 1
	if rcWorkaround then
		txQueueCount = 3
	end
	
	devA = device.config(portA, memory.createMemPool(), 2, txQueueCount + 1)	-- txQueueCount + timerQueue(0)
	devB = device.config(portB, memory.createMemPool(), 2, txQueueCount + 1)
	device.waitForLinks()		
	
	--Set rate relative to txQueueCount
	for i = 1, txQueueCount do
		devA:getTxQueue(i):setRate(rate / txQueueCount)
		devB:getTxQueue(i):setRate(rate / txQueueCount)
	end
	
	devA:l2Filter(0x1234, filter.DROP)
	devB:l2Filter(0x1234, filter.DROP)

	--portA
	dpdk.launchLua("timerSlave", portA, portB, 0, 0)
	dpdk.launchLua("trafficSlave", portA, txQueueCount)

	--portB
	dpdk.launchLua("timerSlave", portB, portA, 0, 0)
	dpdk.launchLua("trafficSlave", portB, txQueueCount)
	
	dpdk.waitForSlaves()
end

function trafficSlave(port, txQueueCount)
	printf("loadSlave: %d", port)
	local queue = {}
	local dev = device.get(port)
	local macS = dev:getMacString()
	local mac = parseMACAddress(macS)
	for i = 1, txQueueCount do
		queue[i] = device.get(port):getTxQueue(i)
	end
	local mem = memory.createMemPool(function(buf)
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		--dst mac
		data[0] = 0x90
		data[1] = 0xe2
		data[2] = 0xba
		data[3] = 0x7e
		data[4] = 0x9f
		if port == 8 then
			data[5] = 0x6d
		else
			data[5] = 0x6c
		end
		
		-- src mac
		for i = 6, 11 do
			data[i] = mac.uint8[i - 6]
		end

		
		
		-- eth type
		data[12] = 0x12
		data[13] = 0x34
	end)
	local MAX_BURST_SIZE = 31
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local totalRecv = 0
	--Diese Zeile ändert nichts an dem ergebnis
	local bufs = mem:bufArray(MAX_BURST_SIZE)
	while dpdk.running() do
		bufs:fill(60)
		
		--Fill the packet with custom information
		for i, buf in ipairs(bufs) do
			buf.refcnt = txQueueCount
		end
		--Send the packets
		for i = 1, txQueueCount do
			totalSent = totalSent + queue[i]:send(bufs)
		end
		
		local time = dpdk.getTime()
		local elapsed = time - lastPrint
		if elapsed > 1 then
			--Sent
			local mpps = (totalSent - lastTotal) / elapsed / 10^6
			printf("IF %d: Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", port, totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			--Received
			local pkts = dev:getRxStats(port)
			totalRecv = totalRecv + pkts
			printf("IF %d: Received %d packets, current rate %.2f Mpps", port, totalRecv, pkts / elapsed / 10^6)
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function timerSlave(txPort, rxPort, txQueue, rxQueue)
	printf("timerSlave: %d --> %d", txPort, rxPort)
	local txDev = device.get(txPort)
	local rxDev = device.get(rxPort)
	local txQueue = txDev:getTxQueue(txQueue)
	local rxQueue = rxDev:getRxQueue(rxQueue)
	local rxMem = memory.createMemPool()	
	local rxBufs = rxMem:bufArray(1)
	--Get MacAdresses
	local rxMac = rxDev:getMac()
	local txMac = txDev:getMac()
	printf("tx: %s, rx: %s", txDev:getMacString(), rxDev:getMacString())
	--Create the Memspace that is sent
	local mem = memory.createMemPool(function(buf)
		local pkt = buf:getEthernetPacket()
		pkt.eth:setDst(rxMac)
		pkt.eth:setSrc(txMac)
		pkt.eth.type = 0xF788
		pkt.payload[0] = 0x00
		pkt.payload[1] = 0x02
	end)
	local bufs = mem:bufArray(1)
	txQueue:enableTimestamps()
	rxQueue:enableTimestamps()
	local hist = {}
	local lastTime = dpdk.getTime()
	--nur zum testen
	local all_tx = 0
	local all_rx = 0
	
	dpdk.sleepMillis(4000)
	while dpdk.running() do
		bufs:fill(60)
		bufs[1].ol_flags = bit.bor(bufs[1].ol_flags, 0x8000)
		-- sync clocks and send
		ts.syncClocks(txDev, rxDev)
		all_tx = all_tx + txQueue:send(bufs)
		-- increment the wait time when using large packets or slower links
		local tx = txQueue:getTimestamp(100)
		local rx = 0
		if tx then
			dpdk.sleepMicros(500) -- minimum latency to limit the packet rate
			-- sent was successful, try to get the packet back (max. 10 ms wait time before we assume the packet is lost)
			rx = rxQueue:tryRecv(rxBufs, 10000)
			if rx > 0 then
				all_rx = all_rx + rx
				local delay = (rxQueue:getTimestamp() - tx) * 6.4
				if delay > 0 and delay < 100000000 then
					hist[delay] = (hist[delay] or 0) + 1
				end
				rxBufs:freeAll()
			end
			
		end
		
		--printing
		local time = dpdk.getTime()
		if (time - lastTime) > 1 then
			printf("timerSlave sent %d packets", all_tx or 0)
			printf("timerSlave received %d packets", all_rx or 0)
			lastTime = time
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
	io.stdout:flush()
end

