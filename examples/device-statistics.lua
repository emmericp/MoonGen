-- This test does the following:
-- 	1. Execute ARP so that the devices exchange MAC-addresses
--	2. Send UDP packets from NIC 1 to NIC 2
-- 	3. Read the statistics from the recieving device
--
-- This script demonstrates how to access device specific statistics ("normal" stats and xstats) via DPDK

local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local ts     = require "timestamping"
local filter = require "filter"
local hist   = require "histogram"
local stats  = require "stats"
local timer  = require "timer"
local arp    = require "proto.arp"
local log    = require "log"

local ffi = require "ffi"

-- set addresses here
local DST_MAC     = nil -- resolved via ARP on GW_IP or DST_IP, can be overriden with a string here
local SRC_IP_BASE = "10.0.0.10"
local DST_IP      = "10.1.0.10"
local SRC_PORT    = 1234
local DST_PORT    = 319

-- answer ARP requests for this IP on the rx port
-- change this if benchmarking something like a NAT device
local RX_IP   = DST_IP
-- used to resolve DST_MAC
local GW_IP   = DST_IP
-- used as source IP to resolve GW_IP to DST_MAC
local ARP_IP  = SRC_IP_BASE


local C = ffi.C

function configure(parser)
	parser:description("Generates UDP traffic and prints out device statistics. Edit the source to modify constants like IPs.")
	parser:argument("txDev", "Device to transmit from."):convert(tonumber)
	parser:argument("rxDev", "Device to receive from."):convert(tonumber)
	parser:option("-r --rate", "Transmit rate in Mbit/s."):default(10000):convert(tonumber)
	parser:option("-s --size", "Packet size."):default(60):convert(tonumber)
end

function master(args)
	txDev = device.config{port = args.txDev, rxQueues = 4, txQueues = 4}
	rxDev = device.config{port = args.rxDev, rxQueues = 4, txQueues = 4}
	device.waitForLinks()
	-- max 1kpps timestamping traffic timestamping
	-- rate will be somewhat off for high-latency links at low rates
	if args.rate > 0 then
		txDev:getTxQueue(0):setRate(args.rate - (args.size + 4) * 8 / 1000)
	end
	rxDev:getTxQueue(0).dev:UdpGenericFilter(rxDev:getRxQueue(3))

	mg.startTask("loadSlave", txDev:getTxQueue(0), rxDev, args.size)
	mg.startTask("receiveSlave", rxDev:getRxQueue(3), args.size)
	arp.startArpTask{
		-- run ARP on both ports
		{ rxQueue = rxDev:getRxQueue(2), txQueue = rxDev:getTxQueue(2), ips = RX_IP },
		-- we need an IP address to do ARP requests on this interface
		{ rxQueue = txDev:getRxQueue(2), txQueue = txDev:getTxQueue(2), ips = ARP_IP }
	}
	mg.waitForTasks()
end

local function fillUdpPacket(buf, len)
	buf:getUdpPacket():fill{
		ethSrc = queue,
		ethDst = DST_MAC,
		ip4Src = SRC_IP,
		ip4Dst = DST_IP,
		udpSrc = SRC_PORT,
		udpDst = DST_PORT,
		pktLength = len
	}
end

local function doArp()
	if not DST_MAC then
		log:info("Performing ARP lookup on %s", GW_IP)
		DST_MAC = arp.blockingLookup(GW_IP, 5)
		if not DST_MAC then
			log:info("ARP lookup failed, using default destination mac address")
			return
		end
	end
	log:info("Destination mac: %s", DST_MAC)
end


--- Runs on the sending NIC
--- Generates UDP traffic and also fetches the stats
function loadSlave(queue, rxDev, size)

	log:info(green("Starting up: LoadSlave"))


	-- retrieve the number of xstats on the recieving NIC
	-- xstats related C definitions are in device.lua
	local numxstats = 0
       	local xstats = ffi.new("struct rte_eth_xstat[?]", numxstats)

	-- because there is no easy function which returns the number of xstats we try to retrieve
	-- the xstats with a zero sized array
	-- if result > numxstats (0 in our case), then result equals the real number of xstats
	local result = C.rte_eth_xstats_get(rxDev.id, xstats, numxstats)
	numxstats = tonumber(result)


	doArp()
	local mempool = memory.createMemPool(function(buf)
		fillUdpPacket(buf, size)
	end)
	local bufs = mempool:bufArray()
	local txCtr = stats:newDevTxCounter(queue, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")
	local baseIP = parseIPAddress(SRC_IP_BASE)

	-- send out UDP packets until the user stops the script
	while mg.running() do
		bufs:alloc(size)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip4.src:set(baseIP)
		end
		-- UDP checksums are optional, so using just IPv4 checksums would be sufficient here
		bufs:offloadUdpChecksums()
		queue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()

	-- retrieve different stats

	log:info(green("---------------------Moongen STATS---------------------------"))

	local stats = rxCtr:getStats()
	for key,value in pairs(stats) do log:info(tostring(key) .. " - " .. tostring(value)) end

	log:info(green("------------------------STATS--------------------------------"))
	local rxStats = rxDev:getStats()
	log:info("ipacktes: " .. tostring(rxStats.ipackets))
	log:info("opacktes: " .. tostring(rxStats.opackets))
	log:info("ibytes: " .. tostring(rxStats.ibytes))
	log:info("obytes: " .. tostring(rxStats.obytes))
	log:info("imissed: " .. tostring(rxStats.imissed))
	log:info("ierrors: " .. tostring(rxStats.ierrors))
	log:info("oerrors: " .. tostring(rxStats.oerrors))
	log:info("rx_nombuf: " .. tostring(rxStats.rx_nombuf))
	log:info("q_ipacktes[0]: " .. tostring(rxStats.q_ipackets[0]))
	log:info("q_ipacktes[1]: " .. tostring(rxStats.q_ipackets[1]))
	log:info("q_ipacktes[2]: " .. tostring(rxStats.q_ipackets[2]))
	log:info("q_ipacktes[3]: " .. tostring(rxStats.q_ipackets[3]))

	-- if no xstats are available we will skip them
	if numxstats > 0 then
		xstats = ffi.new("struct rte_eth_xstat[?]", numxstats)
		C.rte_eth_xstats_get(rxDev.id, xstats, numxstats)
		xstatNames = ffi.new("struct rte_eth_xstat_name[?]", numxstats)
		C.rte_eth_xstats_get_names(rxDev.id, xstatNames, numxstats)
		log:info(green("------------------------XSTATS-------------------------------"))
		log:info("Number of xstats: " .. numxstats)

		for i=0,result-1 do
	   		log:info(ffi.string(xstatNames[i].name, 64) .. ": " .. tostring(xstats[i].value))
		end
	else
		log:warn("This device does not provide any xstats")
	end
end

--- Runs on the recieving NIC
--- Basically tries to fetch a few packets to show some more interesting statistics
function receiveSlave(rxQueue, size)
	log:info(green("Starting up: ReceiveSlave"))
	doArp()

	local mempool = memory.createMemPool()
	local rxBufs = mempool:bufArray()

	-- this will catch a few packet but also cause out_of_buffer errors to show some stats
	while mg.running() do
		rxQueue:tryRecvIdle(rxBufs, 10)
		rxBufs:freeAll()
	end
end
