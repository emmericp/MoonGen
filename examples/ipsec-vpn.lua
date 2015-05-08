local dpdk	= require "dpdk"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"
local stats	= require "stats"

function master(port1, port2)
	if not port1 or not port2 then
		return print("Usage: port1 port2")
	end
	local dev1 = device.config(port1, 1)
	local dev2 = device.config(port2, 1)
	device.waitForLinks()

	ipsec.enable(port1)
	ipsec.disable(port1)

	print("THE END...")
	--dpdk.waitForSlaves()
end

function counterSlave(devices)
	local counters = {}
	for i, dev in ipairs(devices) do
		counters[i] = stats:newDevTxCounter(dev, "plain")
	end
	while dpdk.running() do
		for _, ctr in ipairs(counters) do
			ctr:update()
		end
		dpdk.sleepMillisIdle(10)
	end
	for _, ctr in ipairs(counters) do
		ctr:update()
	end
end


function loadSlave(dev, queue, numFlows)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = queue,
			ethDst = "10:11:12:13:14:15",
			ipDst = "192.168.1.1",
			udpSrc = 1234,
			udpDst = 5678,	
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("10.0.0.1")
	local flow = 0
	local ctr = stats:newDevTxCounter(dev, "plain")
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip.src:set(baseIP + flow)
			flow = incAndWrap(flow, numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		queue:send(bufs)
		ctr:update()
	end
	ctr:finalize()
end

