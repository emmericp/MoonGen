local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local dpdkc		= require "dpdkc"
local filter	= require "filter"


function master(...)
	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		errorf("usage: txPort rxPort [rate]")
	end
	rate = rate or 1000
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
	dpdk.launchLua("loadSlave", txPort, 0)
	dpdk.launchLua("counterSlave", rxPort, 0)
	dpdk.waitForSlaves()
end

function loadSlave(port, queue)
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(31)
	local i = 0
	while dpdk.running() do
		bufs:fill(60)
		for _, buf in ipairs(bufs) do
			buf:setDelay(1500)
			i = i + 1
		end
		totalSent = totalSent + queue:sendWithDelay(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.4f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
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

function timerSlave(txPort, rxPort, txQueue, rxQueue)
	-- TODO add latency (probably when the simplified TS API is finished)
end

