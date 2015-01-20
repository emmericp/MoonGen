local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local dpdkc		= require "dpdkc"
local filter	= require "filter"


function master(...)
	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate (Mpps)]")
	end
	rate = rate or 2
	local txDev, rxDev
	if txPort == rxPort then
		txDev = device.config(txPort, memory.createMemPool(), 1, 1)
		rxDev = txDev
		txDev:wait()
	else
		txDev = device.config(txPort, memory.createMemPool(), 1, 1)
		rxDev = device.config(rxPort, memory.createMemPool(), 1, 1)
		device.waitForDevs(txDev, rxDev)
	end
	dpdk.launchLua("loadSlave", txPort, 0, rate, 60)
	dpdk.waitForSlaves()
end

function loadSlave(port, queue, rate, size)
	local dev = device.get(port)
	local queue = dev:getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getUDPPacket():fill{
			pktLength = size
		}
	end)
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
			local rx = dev:getRxStats(port)
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			printf("Received %d packets, current rate %.2f Mpps", totalReceived, rx / (time - lastPrint) / 10^6)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

function timerSlave(txPort, rxPort, txQueue, rxQueue)
	-- TODO add latency (probably when the simplified TS API is finished)
end

