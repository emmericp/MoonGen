local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local dpdkc	= require "dpdkc"

local ffi	= require "ffi"

function master(...)
	local txPort = tonumberall(...)
	if not txPort then
		errorf("usage: txPort")
	end
	local txDev = device.config(txPort, memory.createMemPool())
	txDev:wait()
	dpdk.launchLua("burstGenSlave", txPort, 10, 100, 6700, 67) -- TODO: consider using command line args here
	dpdk.sleepMillis(100) -- make sure the burst thread starts first
	-- TODO: is there some way to disable TX completely? (or add a cross-thread sync mechanism)
	dpdk.launchLua("loadSlave", txPort, 0)
	dpdk.waitForSlaves()
end

function burstGenSlave(port, rate, burstRate, time, burstTime)
	local queue = device.get(port):getTxQueue(0)
	-- it might be a good idea to move the following into a C function as the JIT could interfere with the timing here
	-- however, initial tests showed no problems (probably because of the extremely small size of the running code)
	while dpdk.running() do
		queue:setRate(rate)
		dpdk.sleepMicros(time)
		queue:setRate(burstRate)
		dpdk.sleepMicros(burstTime)
	end
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
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray()
	local seq = 0
	while dpdk.running() do
		bufs:alloc(60)
		for i = 1, bufs.size do
			local data = ffi.cast("uint32_t*", bufs[i].pkt.data)
			data[4] = seq
			seq = seq + 1
		end
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

