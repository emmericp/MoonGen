local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"

local ffi	= require "ffi"

function master(...)
	local txPort, rxPort = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort")
	end
	local rxMempool = memory.createMemPool()
	local txDev, rxDev
	if txPort == rxPort then
		txDev = device.config(txPort, rxMempool)
		rxDev = txDev
		txDev:wait()
	else
		txDev = device.config(txPort, rxMempool)
		rxDev = device.config(rxPort, rxMempool)
		device.waitForLinks()
	end
	dpdk.launchLua("timerSlave", txPort, rxPort, 0, 0)
	dpdk.waitForSlaves()
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
	dpdk.sleepMillis(1000)
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

