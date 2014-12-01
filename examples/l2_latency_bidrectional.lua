local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"

local ffi	= require "ffi"

--This code works only with one rate for both interfaces(ports) rate must be given in Mbits
function master(...)
	local portA, portB, rate = tonumberall(...)
	if not portA or not portB then
		errorf("usage: Por1t Port2 [rate]")
	end
	rate = rate or 10000
	local rcWorkaround = rate > (64 * 64) / (84 * 84) * 10000 and rate < 10000
	local rxMempool = memory.createMemPool()
	local devA, devB
	if portA == portB then
		errorf("interfaces must differ!");
	else
		devA = device.config(portA, rxMempool, 2, rcWorkaround and 4 or 2)
		devB = device.config(portB, rxMempool, 2, rcWorkaround and 4 or 2)
		device.waitForDevs(devA, devB)
	end
	
	--if rate is too big split the queues into 3
	local txQueueCount = 1;
	if rcWorkaround then
		txQueueCount = 3;
	end	
	--launch threads to send and receive timestamped packets
	dpdk.launchLua("timerSlave", portA, 0, 0)
	dpdk.launchLua("timerSlave", portB, 0, 0)
	
	--start trafficpakets from this core
	dpdk.launchLua("trafficSlave", portA, rate, txQueueCount)
	trafficSlave(portB, rate, txQueueCount)

	dpdk.waitForSlaves()
end



function trafficSlave(port, txRate, txQueueCount)
	--Get device from port
	local dev = device.get(port)
	-- Drop no timestamp packets
	dev:l2Filter(0x1234, filter.DROP)
	
	-- Init sending queues, regarding the given amount
	local queue = {}
	for i = 1, txQueueCount do
		queue[i] = device.get(port):getTxQueue(i)
		queue[i]:setRate(txRate / txQueueCount)
	end
	
	--Create packets without timestamp
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
	
	--receive vars
	local totalRecv = 0
	
	--Sending + receiving
	while dpdk.running() do
		bufs:fill(60)
		--Fill the packet with custom information
		for i, buf in ipairs(bufs) do
			buf.refcnt = txQueueCount
		end
		
		for i = 1, txQueueCount do
			totalSent = totalSent + queue[i]:send(bufs)
		end
		--print every second:
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			--sending stats
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			
			--recv stats
			local pkts = dev:getRxStats(port)
			totalRecv = totalRecv + pkts
			printf("Received %d packets, current rate %.2f Mpps", totalRecv, pkts / (time - lastPrint) / 10^6)
		
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
	printf("Received %d packets", totalRecv)
end

function timerSlave(xPort, txQueue, rxQueue)
	local xDev = device.get(xPort)
	local txQueue = xDev:getTxQueue(txQueue)
	local rxQueue = xDev:getRxQueue(rxQueue)
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
		-- no need to sync clocks while bidirectional
		--ts.syncClocks(txDev, rxDev)
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

