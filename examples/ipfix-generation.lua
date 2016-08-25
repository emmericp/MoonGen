local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local filter	= require "filter"
local stats	= require "stats"
local ffi	= require "ffi"
local headers	= require "headers"
local ipfix	= require "proto.ipfix"

-- Experiment Constants
local IP_SRC		= "192.168.0.1"
local ETH_DST		= "90:e2:ba:1f:8d:44"
local IP_DST		= "10.0.10.10"
local PORT_SRC		= 1234
local PORT_DST		= 4739	-- IPFIX port
local SEND_RATE		= 5	-- MBits/s
local SEND_TIME		= 6000	-- 6 secs
local BURST_TIME	= 2000	-- 2 secs
local RECORDS_PER_PACKET= 1

-- Moongen Constants
local MAX_PKT_SIZE  = 512

-- IPFIX Packet Constants
local PREV_HEADERS_LENGTH	= 42			-- In octets
local OBSERVATION_DOMAIN	= 67108864		-- Observation Domain
local SELECTOR_ALGORITHM	= 1			-- Systematic count-based Sampling
local SAMPLING_PKT_INTERVAL	= 1			-- Sampling Packet Interval
local SAMPLING_PKT_SPACE	= 9999			-- Sampling Packet Space
local PROTO_ID			= { 6, 17 }		-- Protocol Identifier
local SRC_TRANS			= { 80, 100 }		-- Source Transport Port
local DST_TRANS			= { 180, 200 }		-- Destination Transport Port
local IPV4_ADDR			= {parseIPAddress("72.0.0.1"), parseIPAddress("144.255.255.255")} -- Range of IPv4 Addresses

local SEQUENCE_NUMBER	= 0
local TOTAL_MESSAGES	= 0
local TOTAL_FLOWS	= 0

local TMPL_SET =
{
	{id = 8,  length = 4, value = function() return math.random(IPV4_ADDR[1], IPV4_ADDR[2]) end},		-- sourceIPv4Address (ipv4Address)
	{id = 12, length = 4, value = function() return math.random(IPV4_ADDR[1], IPV4_ADDR[2]) end},		-- destinationIPv4Address(ipv4Address)
	{id = 4,  length = 1, value = function() return PROTO_ID[math.random(table.getn(PROTO_ID))] end},	-- protocolIdentifier (unsigned8)
	{id = 7,  length = 2, value = function() return math.random(SRC_TRANS[1], SRC_TRANS[2]) end},		-- sourceTransportPort (unsigned16)
	{id = 11, length = 2, value = function() return math.random(DST_TRANS[1], DST_TRANS[2]) end}		-- destinationTransportPort (unsigned16)
}

local OPTS_TMPL_SET =
{
	{id = 149, length = 4, value = function() return OBSERVATION_DOMAIN end},	-- observationDomainId (unsigned32)
	{id = 304, length = 2, value = function() return SELECTOR_ALGORITHM end},	-- selectorAlgorithm (unsigned16)
	{id = 305, length = 4, value = function() return SAMPLING_PKT_INTERVAL end},	-- samplingPacketInterval (unsigned32)
	{id = 306, length = 4, value = function() return SAMPLING_PKT_SPACE end}	-- samplingPacketSpace (unsigned32)
}

--- Main function and entry point for each MoonGen's script. Its funcion is to configure queues
--- and filters on the used NICs and then start one or more slave tasks. It also configures the
--- rates at which the exporting process sends the packets.
--- @param txPort NIC's port
--- @param rate rate at which packets will be sent
--- @param recordsPerPkt number of data records per packet
--- @param burst if burst == 1, then generate bursty traffic
function master(txPort, rate, recordsPerPkt, burst)
	if not txPort then
		return print("usage: txPort [rate [recordsPerPkt [burst]]]")
	end

	-- if rate is not provided then use a default value of 2.5 MBits/s
	rate = rate or SEND_RATE
	time = SEND_TIME

	-- if recordsPerPkt is not provided then use a default value of 1 record per packet
	recordsPerPkt = recordsPerPkt or RECORDS_PER_PACKET

	-- double rate for bursty traffic
	burstRate = rate * 2

	local speed = 0

	-- the minimum rate of the hardware rate control is 0.1% of the link rate, i.e. 10 mbit/s.
	-- for lower rates we have to configure the link rate speed to a slower rate
	-- i.e. rate = 1 mbit/s, link rate = 1 Gbit/s
	if (rate < 10) then
		speed = 1000
	end

	-- configure tx device
	local txDev = device.config({port = txPort, rxQueues = 2, txQueues = 3, speed = speed})
	txDev:getTxQueue(0):setRate(rate)

	-- wait until the links are up
	device.waitForLinks()

	printf("Sending %f MBit/s IPFIX traffic to UDP port %d", rate, PORT_DST)

	if burst == 1 then
		-- start burst slave (rate manager)
		dpdk.launchLua("ipfixBurstSlave", txDev:getTxQueue(0), rate, SEND_TIME, burstRate, BURST_TIME)
	end

	-- start ipfx slave (exporting process)
	dpdk.launchLua("ipfixSlave", txDev:getTxQueue(0), recordsPerPkt, PORT_DST)

	-- wait until all tasks are finished
	dpdk.waitForSlaves()
end

--- Task that modifies the rates at which the exporting process sends packets
--- to the collector process. This prove to be very useful during our testing
--- as it enabled us to simulate a more real scenario in which rates are not constants.
--- @param queue NIC's queue over which packets are sent
--- @param rate normal rate at which packets will be sent
--- @param time normal time lapse in which "normal" traffic is generated
--- @param burstRate burst rate at which packets will be sent
--- @param burstTime burst time lapse in which "normal" traffic is generated
function ipfixBurstSlave(queue, rate, time, burstRate, burstTime)
	-- wait for the ipfixSlave task to start
	dpdk.sleepMillis(100)
	while dpdk.running() do
		-- set normal rate and wait before switch to burst rate
		queue:setRate(rate)
		dpdk.sleepMillis(time)

		-- set burst rate and wait before switch to normal rate
		queue:setRate(burstRate)
		dpdk.sleepMillis(burstTime)
	end
end

--- Generates and sends ipfix packets to the collector process.
--- @param queue NIC's queue over which packets are sent
--- @param recordsPerPkt number of data records per packet
--- @param port Tx port
function ipfixSlave(queue, recordsPerPkt, port)
	local mem = memory.createMemPool(function(buf)
		-- creates an ipfix packet with the following values
		buf:getIpfixPacket():fill{
			-- creates an ipfix packet with the following values
			ethSrc = queue,
			ethDst = ETH_DST,
			ip4Src = IP_SRC,
			ip4Dst = IP_DST,
			udpSrc = PORT_SRC,
			udpDst = port,
			ipfixObservationDomain = OBSERVATION_DOMAIN
		}
		-- for values not set in here, MoonGen uses the default
		-- values specified in lua/include/proto/ipfix.lua
	end)

	local txCtr = stats:newManualTxCounter("Port " .. port, "plain")

	local bufs = mem:bufArray()
	local isFirst = true
	local tmplLength = ipfix:getRecordLength(TMPL_SET)
	local optsTmplLength = ipfix:getRecordLength(OPTS_TMPL_SET)
	local pktSize = 0

	-- stats counters
	local deltaTime = dpdk.getTime()
	local deltaFlows = 0
	local deltaPkts = 0
	local deltaBytes = 0

	-- creates histogram.csv file and writes its headers
	local histFile = io.open("histogram.csv", "w+")
	histFile:write("delta_time,delta_flows,delta_packets,delta_bytes\n")
	histFile:flush()

	while dpdk.running() do
		-- allocate buffers from the mem pool and store them in this array
		bufs:alloc(MAX_PKT_SIZE)

		for _, buf in ipairs(bufs) do
			local pkt = buf:getIpfixPacket()
			local msgSize = 0

			-- modify packet's fields
			pkt.ipfix:setExportTime(os.time())
			pkt.ipfix:setSeq(SEQUENCE_NUMBER)

			if isFirst then -- Create template set only the first time
				-- Create template set
				local tmplSet = ipfix:createTmplSet(998, TMPL_SET)
				msgSize = ipfix:copyTo(pkt.payload.uint8, 0, tmplSet)

				-- Create data set
				local dataSet = ipfix:createDataSet(998, TMPL_SET, tmplLength, 1)
				msgSize = ipfix:copyTo(pkt.payload.uint8, msgSize, dataSet)
				TOTAL_FLOWS = TOTAL_FLOWS + 1
				SEQUENCE_NUMBER = SEQUENCE_NUMBER + 1

				isFirst = false
			else -- Create only data sets
				local dataSet = ipfix:createDataSet(998, TMPL_SET, tmplLength, recordsPerPkt)
				msgSize = ipfix:copyTo(pkt.payload.uint8, 0, dataSet)
				TOTAL_FLOWS = TOTAL_FLOWS + recordsPerPkt
				SEQUENCE_NUMBER = SEQUENCE_NUMBER + recordsPerPkt
			end

			-- packet's size is given by the sum of the IPFIX headers and  message length
			-- plus previous headers length e.g. (eth, ip4, udp)
			pktSize = msgSize + PREV_HEADERS_LENGTH + ipfix:getHeadersLength()
			pkt:setLength(pktSize)
			buf:setSize(pktSize)

			-- update exportedMessageTotalCount value
			TOTAL_MESSAGES = TOTAL_MESSAGES + 1
		end
		-- send packets
		bufs:offloadUdpChecksums()
		txCtr:updateWithSize(queue:send(bufs), pktSize)

		-- update stats
		local time = dpdk.getTime()
		if time - deltaTime >= 1 then
			deltaTime = time - deltaTime
			deltaFlows = SEQUENCE_NUMBER - deltaFlows
			deltaPkts = txCtr.total - deltaPkts
			deltaBytes = txCtr.totalBytes - deltaBytes

			-- write stats
			histFile:write(("%s,%s,%s,%s\n"):format(deltaTime, deltaFlows, deltaPkts, deltaBytes))
			histFile:flush()

			deltaTime = time
			deltaFlows = SEQUENCE_NUMBER
			deltaPkts = txCtr.total
			deltaBytes = txCtr.totalBytes
		end
	end

	txCtr:finalize()

	-- update stats
	deltaTime = dpdk.getTime() - deltaTime
	deltaFlows = SEQUENCE_NUMBER - deltaFlows
	deltaPkts = txCtr.total - deltaPkts
	deltaBytes = txCtr.totalBytes - deltaBytes

	-- write stats
	histFile:write(("%s,%s,%s,%s\n"):format(deltaTime, deltaFlows, deltaPkts, deltaBytes))
	histFile:flush()
	histFile:close()
end
