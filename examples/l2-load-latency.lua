local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"
local histogram	= require "histogram"

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
		device.waitForDevs(txDev, rxDev)
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
		bufs:fill(60)
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			fprintf(io.stdout, "Sent,%d,%.2f\n", totalSent, mpps, mpps)
			fprintf(io.stderr, "Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate\n", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	fprintf(io.stdout, "TotalSent,%d\n", totalSent)
	fprintf(io.stderr, "Sent %d packets in total\n", totalSent)
end

function counterSlave(port)
	local dev = device.get(port)
	dev:l2Filter(0x1234, filter.DROP)
	local total = 0
	while dpdk.running() do
		local time = dpdk.getTime()
		dpdk.sleepMillis(1000)
		local elapsed = dpdk.getTime() - time
		local pkts = dev:getRxStats(port)
		total = total + pkts
		fprintf(io.stdout, "Received,%d,%.2f\n", total, pkts / elapsed / 10^6)
		fprintf(io.stderr, "Received %d packets, current rate %.2f Mpps\n", total, pkts / elapsed / 10^6)
	end
	fprintf(io.stdout,"TotalReceived,%d\n",total)
	fprintf(io.stderr, "Received %d packets\n", total)
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
	local hist = histogram:create()
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
				-- for i = -- TODO: loop over packets and check for 0x0400 ol_flag 
				local delay = (rxQueue:getTimestamp() - tx) * 6.4
				if delay > 0 and delay < 100000000 then
					hist:update(delay)
				end
				rxBufs:freeAll()
			end
		end
	end
	hist:stat()
	for _, v in ipairs(hist.sortedHisto) do
		fprintf("HistoSample,%f,%d\n",v.k,v.v)
	end
	fprintf(io.stderr, "HistoHead,Samples,Avg,LowerQuartile,Median,UpperQuartile\n")
	fprintf(io.stdout, "HistoStat,%d,%f,%f,%f,%f\n", hist.samples, hist.avg, hist.lower_quart, hist.median, hist.upper_quart)
	io.stdout:flush()
	io.stderr:flush()
end

