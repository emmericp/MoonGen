--! @file write-benchmark.lua
--! @brief Benchmarks the pcapWriter

local mg		= require "dpdk"
local memory		= require "memory"
local device		= require "device"
local log		= require "log"
local ts 		= require "timestamping"
local pcap		= require "pcap"
local stats		= require "stats"

local PKT_SIZE = {60, 80, 120, 500, 1024} -- size for randomly generated packets
local BUF_LEN = { 12, 24, 48, 100, 200 } -- number of packets in bufarray

--local PKT_SIZE = { 60 }
--local BUF_LEN = { 12 }

function master(source, sink, maxp)
	if source == '--help' then
		return log:info([[

Usage: [source pcap] [sink pcap] [maxp]

Reads maxp UDP packets from the source pcap to the sink pcap.

if source is set to '-', random UDP packets are generated and written to sink.
The default value for source is '-'.
The default value for sink is test-sink.pcap.
]])
	end
	source = source or "-"
	sink = sink or "test-sink.pcap"
	maxp = maxp and tonumber(maxp) or 10^7

	-- test demonstration without usage of network interfaces
	simplePcapStoreAndLoadTestSlave(source, sink, maxp)

	mg.waitForSlaves()
end


--! @brief most simpliest test; just store a packet from buffer to pcap file, and read it again
function simplePcapStoreAndLoadTestSlave(source, sink, maxp)
	print("maxp =",maxp)

	-- allocate empty mempool or mempool with generator for udp packets with random src port
	local mem = 
		source == '-' and memory.createMemPool(function(buf)
			buf:getUdpPacket():fill({udpSrc=math.floor(math.random()*65535)})
			end)
		or memory.createMemPool()


	for i, pktSize in ipairs(PKT_SIZE) do
		for k,bufLen in ipairs(BUF_LEN) do
			print("Benchmarking "..pktSize.." Byte packets in "..bufLen.." long buffers")
			local bufs = mem:bufArray(bufLen)
			bufs:alloc(pktSize)
			if not mg.running then break end

			local counter = stats:newManualRxCounter("Writing "..pktSize.." bytes packets in "..bufLen.." buffer batches")
			local pcapWriter = pcapWriter:newPcapWriter(sink)

			while counter.total + counter.current < maxp do
				pcapWriter:write(bufs)
				local bytes = 0
				for i=1,#bufs do bytes = bytes + bufs[i].pkt.pkt_len end
				counter:update(#bufs, bytes)
			end

			pcapWriter:close()
			counter:finalize()
			bufs:free(bufLen)
		end
	end
end
