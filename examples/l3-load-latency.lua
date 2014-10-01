local dpdk	= require "dpdk"
local memory	= require "memory"
local dev	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"

local ffi	= require "ffi"

function master(...)
	local txPort, rxPort, rate, size = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort")
	end
	rate = rate or 1
	size = size or 128
	local rxMempool = memory.createMemPool(2047)
	if txPort == rxPort then
		dev.config(txPort, rxMempool, 2, 2)
	else
		dev.config(txPort, rxMempool, 1, 2)
		dev.config(rxPort, rxMempool, 2, 1)
	end
	dev.waitForPorts(txPort, rxPort)
	dev.setTxRate(txPort, 0, rate)
	dpdkc.rte_eth_promiscuous_disable(rxPort)
	dpdk.setRuntime(20)
	dpdk.launchLua("timerSlave", txPort, rxPort, 1, 0)
	dpdk.launchLua("loadSlave", txPort, 0, size)
	dpdk.launchLua("counterSlave", rxPort, 0, size)
	dpdk.waitForSlaves()
end

function loadSlave(port, queue, size)
	local NUM_BUFS = 1023
	local mempool = memory.createMemPool(NUM_BUFS)
	local bufs = {}
	for i = 1, NUM_BUFS do
		local buf = memory.alloc(mempool)
		ts.fillPacket(buf, 1234) 
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		-- dst mac
		data[0] = 0x00
		data[1] = 0x11
		data[2] = 0x22
		data[3] = 0x33
		data[4] = 0x44
		data[5] = 0xff
		-- src mac
		for i = 6, 11 do
			data[i] = i
		end
		data[43] = 0x00 -- PTP version, set to 0 to disable timestamping for load packets
		data[58] = 0x00 -- timestamp indicator
		data[59] = 0x00
		bufs[#bufs + 1] = buf
	end
	for i, v in ipairs(bufs) do
		dpdkc.rte_pktmbuf_free_export(v)
	end
	local MAX_BURST_SIZE = 31
	local bufs = ffi.new("struct rte_mbuf*[?]", MAX_BURST_SIZE)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local lastTime = dpdk.getTime()
	while dpdk.running() do
		local burstSize = MAX_BURST_SIZE
		for i = 0, MAX_BURST_SIZE - 1 do
			-- this should be hidden behind some API...
			local buf = memory.alloc(mempool)
			buf.pkt.pkt_len = size - 4
			buf.pkt.data_len = size - 4
			if  buf == nil then
				i = i - 1
			else
				bufs[i] = buf
			end
		end
		local sent = 0
		while true do
			sent = sent + dpdkc.rte_eth_tx_burst_export(port, queue, bufs + sent, MAX_BURST_SIZE - sent)
			if sent >= MAX_BURST_SIZE then
				break
			end
		end
		totalSent = totalSent + sent
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s", totalSent, mpps, mpps * (size + 20) * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function counterSlave(port)
	--filter.l2Filter(port, 0x0800, 63) -- routings packets to a queue that doesn't exist drops them
	local total = 0
	while dpdk.running() do
		local time = dpdk.getTime()
		dpdkc.rte_delay_ms_export(1000)
		local elapsed = dpdk.getTime() - time
		local pkts = dev.getRxStats(port)
		total = total + pkts
		printf("Received %d packets, current rate %.2f Mpps", total, pkts / elapsed / 10^6)
	end
	printf("Received %d packets", total)
end

function timerSlave(txPort, rxPort, txQueue, rxQueue, size)
	local bufs = ffi.new("struct rte_mbuf*[?]", 1)
	local rxBufs = ffi.new("struct rte_mbuf*[?]", 32)
	ts.enableTimestamps(txPort, 0) -- TODO: split enableTimestamps into rx and tx
	ts.enableTimestamps(rxPort, rxQueue, 1234)
	local hist = {}
	local mempool = memory.createMemPool(1024)
	local lastSent = 0
	while dpdk.running() do
		local tx
		-- send with simple rate control
		local sent = false
		if dpdk.getTime() - lastSent >= 0.002 then -- max rate: about 500 packets/s
			lastSent = dpdk.getTime()
			sent = true
			bufs[0] = memory.alloc(mempool)
			ts.fillPacket(bufs[0], 1234, size)
			local data = ffi.cast("uint8_t*", bufs[0].pkt.data)
		data[0] = 0x00
		data[1] = 0x11
		data[2] = 0x22
		data[3] = 0x33
		data[4] = 0x44
		data[5] = 0xff
			ts.syncClocks(txPort, rxPort)
			while dpdkc.rte_eth_tx_burst_export(txPort, txQueue, bufs, 1) == 0 do end
			for i = 1, 100 do
				tx = ts.tryReadTxTimestamp(txPort)
				if tx then
					break
				end
				dpdkc.rte_delay_us_export(10)
			end
		end
		-- receive
		-- TODO: dynamically adjust the max wait time
		local tries = 3000 -- wait for max 3 ms, assume as lost otherwise
		while tries > 0 do
			local recv
			repeat
				recv = dpdkc.rte_eth_rx_burst_export(rxPort, rxQueue, rxBufs, 32) 
			until recv ~= 0 or not dpdk.running()
			local found = false
			for i = 0, recv - 1 do
				local data = ffi.cast("uint8_t*", rxBufs[i].pkt.data)
				if data[58] == 0x54 then -- TS packet, yay
					found = true
				end
				dpdkc.rte_pktmbuf_free_export(rxBufs[i])
			end
			if found or not sent then
				break
			end
			if recv < 20 then
				tries = tries - 1
				dpdkc.rte_delay_us_export(1);
			end
		end
		if tries > 0 and tx and sent then
			local delay = (ts.readRxTimestamp(rxPort) - tx) * 6.4
			if delay > 0 and delay < 100000000 then
				hist[delay] = (hist[delay] or 0) + 1
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
	local avg = sum / samples
	-- calc stddev
	-- TODO: move to a separate function
	local stddev = 0
	for k, v in pairs(hist) do
		stddev = stddev + (k - avg)^2 * v
	end
	local stddev = math.sqrt(stddev / samples)
	print()
	print("Average: " .. avg .. " ns, stddev: " .. stddev .. " ns, samples: " .. samples)
	print("----------------------------------------------")
	io.stdout:flush()
end

