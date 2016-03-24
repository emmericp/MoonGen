--! @file pcap-test.lua
--! @brief This is a simple test for MoonGen's pcap import and export functionality

local mg		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local log		= require "log"
local ts 		= require "timestamping"
local pcap		= require "pcap"

function master(source, sink)
	source = source or "-"
	sink = sink or "test-sink.pcap"

	if source == '--help' then
		return log:info([[

Usage: [source pcap] [sink pcap]

Reads UDP packets from the source pcap to the sink pcap.

if source is set to '-', some random UDP packets are generated and written to sink.
The default value for source is '-'.
The default value for sink is test-sink.pcap.
]])
	end
	source = source or "-"
	sink = sink or "test-sink.pcap"

	-- test demonstration without usage of network interfaces
	simplePcapStoreAndLoadTestSlave(source, sink)

	mg.waitForSlaves()
end


--! @brief most simpliest test; just store a packet from buffer to pcap file, and read it again
function simplePcapStoreAndLoadTestSlave(source, sink)

	-- allocate mempool with generator for udp packets with random src port
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill({udpSrc=math.floor(math.random()*65535)})
	end)
	local bufs = mem:bufArray(12)
	bufs:alloc(124)

	-- read packets from a pcap if the user provided one
	if source ~= '-' then
		local pcapReader = pcapReader:newPcapReader(source)
		for i = 1,12 do
			if pcapReader.done then break end
			pcapReader:readPkt(bufs[i])
			print('Read UDP packet with src port '..bufs[i]:getUdpPacket().udp:getSrcPortString())
		end
		pcapReader:close()
	-- log randomly generated packets instead
	else
		print("Simple test: Generating random packets, writing to "..sink.." and reading back from "..sink)
		for i = 1,12 do
			print('Generated UDP packet with src port '..bufs[i]:getUdpPacket().udp:getSrcPortString())
		end
	end

	-- write the packets
	local pcapWriter = pcapWriter:newPcapWriter(sink)
	for i = 1,12 do
		pcapWriter:writePkt(bufs[i])
	end
	pcapWriter:close()

	-- read back
	local pcapReader = pcapReader:newPcapReader(sink) -- yes, open sink, not source
	while not pcapReader.done do
		pcapReader:readPkt(bufs[1])
		print('Read back UDP packet with src port '..bufs[1]:getUdpPacket().udp:getSrcPortString())
	end

end
