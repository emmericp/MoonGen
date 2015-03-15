local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"

local ffi	= require "ffi"

function master(...)
	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate]")
	end
	rate = rate or 10000
	local rcWorkaround = rate > (64 * 64) / (84 * 84) * 10000 and rate < 10000
	local rxMempool = memory.createMemPool()
	local txDev, rxDev
	if txPort == rxPort then
		txDev = device.config(txPort, rxMempool, 2, rcWorkaround and 4 or 2)
		rxDev = txDev
		txDev:wait()
	else
		txDev = device.config(txPort, rxMempool, 1, rcWorkaround and 4 or 2)
		rxDev = device.config(rxPort, rxMempool, 2, 1)
		device.waitForLinks()
	end
	if rcWorkaround then
		txDev:getTxQueue(0):setRate(rate / 3)
		txDev:getTxQueue(2):setRate(rate / 3)
		txDev:getTxQueue(3):setRate(rate / 3)
	else
		txDev:getTxQueue(0):setRate(rate)
	end
	dpdk.launchLua("timerSlave", txPort, rxPort, 1, 1)
	dpdk.launchLua("loadSlave", txPort, 0)
	dpdk.launchLua("counterSlave", rxPort, 0)
	if rcWorkaround then
		dpdk.launchLua("loadSlave", txPort, 2)
		dpdk.launchLua("loadSlave", txPort, 3)
	end
	dpdk.waitForSlaves()
end

function loadSlave(port, queue)
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		-- src/dst mac
		for i = 0, 11 do
			data[i] = i
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
	local bufs = mem:bufArray(MAX_BURST_SIZE)
	while dpdk.running() do
		bufs:alloc(60)
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function counterSlave(port)
	local dev = device.get(port)
	dev:l2Filter(0x1234, filter.DROP)
	local total = 0
	while dpdk.running(500) do
		local time = dpdk.getTime()
		dpdk.sleepMillis(1000)
		local elapsed = dpdk.getTime() - time
		local pkts = dev:getRxStats(port)
		total = total + pkts
		printf("Received %d packets, current rate %.2f Mpps", total, pkts / elapsed / 10^6)
	end
	printf("Received %d packets", total)
end

function timerSlave(txPort, rxPort, txQueue, rxQueue)
	local txDev = device.get(txPort)
	local rxDev = device.get(rxPort)
	local txQueue = txDev:getTxQueue(txQueue)
	local rxQueue = rxDev:getRxQueue(rxQueue)
	local mem = memory.createMemPool()
	local buf = mem:bufArray(1)
	local rxBufs = mem:bufArray(2)
	txQueue:enableTimestamps()
	rxQueue:enableTimestamps()
	local hist = {}
	dpdk.sleepMillis(4000)
	while dpdk.running() do
		buf:alloc(60)
		ts.fillL2Packet(buf[1])
		-- sync clocks and send
		ts.syncClocks(txDev, rxDev)
		txQueue:send(buf)
		-- increment the wait time when using large packets or slower links
		local tx = txQueue:getTimestamp(100)
		if tx then
			dpdk.sleepMicros(500) -- minimum latency to limit the packet rate
			-- sent was successful, try to get the packet back (max. 10 ms wait time before we assume the packet is lost)
			local rx = rxQueue:tryRecv(rxBufs, 10000)
			if rx > 0 then
				-- for i = -- TODO: loop over packets and check for 0x0400 ol_flag 
				local delay = (rxQueue:getTimestamp() - tx) * 6.4
				if delay > 0 and delay < 100000000 then
					hist[delay] = (hist[delay] or 0) + 1
				end
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
	io.stdout:flush()
end

