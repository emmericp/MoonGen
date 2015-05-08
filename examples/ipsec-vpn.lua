local dpdk	= require "dpdk"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"

function master(txPort, rxPort)
	if not txPort or not rxPort then
		return print("Usage: txPort rxPort")
	end
	local txDev = device.config(txPort, 1)
	local rxDev = device.config(rxPort, 1)
	device.waitForLinks()

	dpdk.launchLua("rxSlave", rxPort)
	dpdk.launchLua("txSlave", txPort, txDev:getTxQueue(0), rxDev:getRxQueue(0))

	dpdk.waitForSlaves()
	print("THE END...")
end

-- txSlave sends out (ipsec crypto) packages
function txSlave(port, srcQueue, dstQueue)
	local numFlows = 1
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = srcQueue,
			ethDst = dstQueue,
			ipDst = "192.168.1.1",
			udpSrc = 1234,
			udpDst = 5678,	
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("10.0.0.1")
	local flow = 0

	ipsec.enable(port)
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip.src:set(baseIP + flow)
			flow = incAndWrap(flow, numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		srcQueue:send(bufs)
	end
	ipsec.disable(port)
end

-- rxSlave logs received packages
function rxSlave(port)
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

