local dpdk		= require "dpdk"
local memory	= require "memory"
local ts		= require "timestamping"
local device	= require "device"
local filter	= require "filter"

function master(...)
	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate (Mpps)]")
	end
	rate = rate or 2
	local txDev = device.config(txPort, 2, 2)
	local rxDev = device.config(rxPort, 2, 2)
	device.waitFor(txDev, rxDev)
	dpdk.launchLua("loadSlave", txDev, rxDev, txDev:getTxQueue(0), rate, 60)
	dpdk.launchLua("timerSlave", txDev, rxDev, txDev:getTxQueue(1), rxDev:getRxQueue(1), 60)
	dpdk.waitForSlaves()
end

function loadSlave(dev, rxDev, queue, rate, size)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	rxDev:l2Filter(0x1234, filter.DROP)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local totalReceived = 0
	local bufs = mem:bufArray(31)
	while dpdk.running() do
		bufs:fill(size)
		for _, buf in ipairs(bufs) do
			-- this script uses Mpps instead of Mbit (like the other scripts)
			buf:setDelay(poissonDelay(10^10 / 8 / (rate * 10^6) - size - 24))
		end
		totalSent = totalSent + queue:sendWithDelay(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local rx = rxDev:getRxStats()
			totalReceived = totalReceived + rx
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			printf("Received %d packets, current rate %.2f Mpps", totalReceived, rx / (time - lastPrint) / 10^6)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function timerSlave(txDev, rxDev, txQueue, rxQueue)
	local mem = memory.createMemPool()
	local buf = mem:bufArray(1)
	local rxBufs = mem:bufArray(2)
	txQueue:enableTimestamps()
	rxQueue:enableTimestamps()
	local hist = {}
	dpdk.sleepMillis(4000)
	while dpdk.running() do
		buf:fill(60)
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

