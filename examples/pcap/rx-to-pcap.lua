--! @file rx-to-pcap.lua
--! @brief Capture to Pcap with software timestamping

local mg		= require "dpdk"
local memory		= require "memory"
local device		= require "device"
local log		= require "log"
local ts 		= require "timestamping"
local pcap		= require "pcap"
local ffi		= require "ffi"
local stats		= require "stats"

function master(rxPort, maxp, sink)
	if not rxPort then
		return log:info([[

Usage: rxPort [maxp] [sink]

Reads packets from rxPort and writes them to sink.
Reads at most maxp packets or forever if maxp == 0

Example usage:
sudo ./build/MoonGen examples/pcap-test.lua 0			# reads packets from port 0 to pcap-port-0.pcap forever
sudo ./build/MoonGen examples/pcap-test.lua 1 100 foo.pcap	# reads 100 packets from port 1 to foo.pcap
]])
	end
	sink = sink or 'pcap-port-'..rxPort..'.pcap'
	maxp = maxp or 0
	local rxDev = device.config{ port = rxPort, rxQueues = 1 }
	mg.sleepMillis(100)
		
	mg.launchLua("pcapSinkSlave", rxDev:getRxQueue(0), rxDev, sink, maxp)
	mg.sleepMillis(50)

	mg.waitForSlaves()
end



--! @brief: receive and store packets with software timestamps
function pcapSinkSlave(queue, rxDev, sink, maxp)
	print('pcapSinkSlave is running')
	local numbufs = (maxp == 0) and 100 or math.min(100, maxp)
	local bufs = memory.bufArray(numbufs)
	local timestamps = ffi.new("uint64_t[?]", numbufs)

	local pcapSinkWriter = pcapWriter:newPcapWriter(sink)
	local ctr = stats:newDevRxCounter(rxDev, "plain")
	local pkts = 0
	while mg.running() and (maxp == 0 or pkts < maxp) do
		local rxnum = (maxp == 0) and #bufs or math.min(#bufs, maxp - pkts)
		local rx = queue:recvWithTimestamps(bufs, timestamps, rxnum)
		pcapSinkWriter:writeTSC(bufs, timestamps, rx, true)
		pkts = pkts + rx
		ctr:update()
		bufs:free(rx)
	end
	print('pcapSinkSlave terminated after receiving '..pkts.." packets")
	bufs:freeAll()

	ctr:finalize()
	pcapSinkWriter:close()
end
