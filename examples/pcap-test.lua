--! @file pcap-test.lua
--! @brief This is a simple test for MoonGen's pcap inport and export functionality

local mg		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local log		= require "log"
local pcap		= require "pcap"

function master(txPort, rxPort)
	if not txPort or not rxPort then
		return log:info("usage: txPort rxPort")
	end
	local txDev, rxDev
	if txPort == rxPort then
		-- sending and receiving from the same port
		txDev = device.config{ port = rxPort, rxQueues = 1, txQueues = 1}
		rxDev = txDev
	else
		-- two different ports, different configuration
		txDev = device.config{ port = txPort, txQueues = 1 }
		rxDev = device.config{ port = rxPort, rxQueues = 1 }
	end
	mg.sleepMillis(100)
	-- test demonstration without usage of network interfaces
	simplePcapStoreAndLoadTestSlave()
	-- send and receive test
	mg.launchLua("pcapSinkSlave", rxDev:getRxQueue(0))
	mg.sleepMillis(50)
	mg.launchLua("pcapLoadSlave", txDev:getTxQueue(0))
	mg.waitForSlaves()
end


--! @brief most simpliest test; just store a packet from buffer to pcap file, and read it again
function simplePcapStoreAndLoadTestSlave()
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill()
	end)
	local bufs = mem:bufArray()
	bufs:alloc(124)
	local pcapWriter = pcapWriter:newPcapWriter("test-load.pcap")
	local pkt = bufs[1]:getUdpPacket()
	-- make some weired change to test
	pkt.udp:setSrcPort(42)
	pcapWriter:writePkt(bufs[1])
	local pcapReader = pcapReader:newPcapReader("test-load.pcap")
	pkt = bufs[2]:getUdpPacket()
	pcapReader:readPkt(bufs[2])
	pcapReader:close()
	pcapWriter:writePkt(bufs[2])
	pcapWriter:close()
	print("packet (with srcport: " .. pkt.udp:getSrcPortString() .. ") was read from the pcap: " .. pkt.udp:getString())
end

--! @brief: sends a packet out
function pcapLoadSlave(queue)
	print('pcapLoadSlave is running')
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill()
	end)
	-- a buf array is essentially a very thin wrapper around a rte_mbuf*[], i.e. an array of pointers to packet buffers
	local bufs = mem:bufArray()
	bufs:alloc(124)
	local pcapReader = pcapReader:newPcapReader("test-load.pcap")
	print('pcapReader created')
	pcapReader:readPkt(bufs[1])
	print('read one packet from test-load.pcap')
	bufs:offloadUdpChecksums()
	queue:send(bufs)
	print('packet sent')
end

--! @brief: receive and stroe the packet
function pcapSinkSlave(queue)
	print('pcapSingSlave is running')
	local bufs = memory.bufArray()
	local pcapSinkWriter = pcapWriter:newPcapWriter("test-sink.pcap")
	print('pcapSinkWriter created')
	while mg.running() do
		local rx = queue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			pcapSinkWriter:writePkt(buf)
			local pkt = buf:getUdpPacket()
			print("the following packet was received and stored to \"test-sink.pcap\": " .. pkt.udp:getString())
			mg.stop()
		end
		bufs:freeAll()
	end
	pcapSinkWriter:close()
end