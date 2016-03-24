--! @file pcap-test.lua
--! @brief This is a simple test for MoonGen's pcap inport and export functionality

local mg		= require "dpdk"
local memory		= require "memory"
local device		= require "device"
local log		= require "log"
local ts 		= require "timestamping"
local pcap		= require "pcap"
local ffi		= require "ffi"

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
		
	mg.launchLua("pcapSinkSlave", rxDev:getRxQueue(0), sink, maxp)
	mg.sleepMillis(50)

	mg.waitForSlaves()
end



--! @brief: receive and store packets
function pcapSinkSlave(queue, sink, maxp)
	--queue:enableTimestamps()
	print('pcapSinkSlave is running')
	local numbufs = 100
	if maxp ~= 0 then numbufs = math.min(100, maxp) end
	local bufs = memory.bufArray(numbufs)
	local timestamps = ffi.new("uint64_t["..numbufs.."]")
	local pcapSinkWriter = pcapWriter:newPcapWriter(sink)
	print('pcapSinkWriter created')
	local pkts = 0
	while mg.running() and (maxp == 0 or pkts < maxp) do
		local rxnum = #bufs
		if maxp ~= 0 then rxnum = math.min(#bufs, maxp - pkts) end
		local rx = queue:recvWithTimestamps(bufs, timestamps, rxnum)
		for i = 1, rx do
			local buf = bufs[i]
			pcapSinkWriter:writePkt(buf, timestamps[i-1])
			local pkt = buf:getUdpPacket()
			print(pkt.udp:getString()," => ", sink)
		end
		pkts = pkts + rx
	end
	print('pcapSinkSlave terminated after receiving '..pkts.." packets")
	bufs:freeAll()
	pcapSinkWriter:close()
end
