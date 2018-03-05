local mg		= require "moongen"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local log		= require "log"
local ip4		= require "proto.ip4"
local libmoon	= require "libmoon"


function configure(parser)
	-- do nothing, just check parse errors
	function convertMac_fake(str)
		mac = parseMacAddress(str, true)
		if not mac then
			parser:error("failed to parse MAC "..str)
		end
		return str
	end

	function convertTime(str)
		local pattern = "^(%d+)([mu]?s)$"
		local _, _, n, unit = string.find(str, pattern)
		if not (n and unit) then
			parser:error("failed to parse time '"..str.."', it should match '"..pattern.."' pattern")
		end
		return {n=tonumber(n), unit=unit}
	end

	parser:description("Generates TCP SYN flood from varying source IPs, supports both IPv4 and IPv6")
	parser:argument("dev", "Devices to transmit from."):args("*"):convert(tonumber)
	parser:option("-r --rate", "Transmit rate in Mbit/s."):default(10000):convert(tonumber)
	parser:option("-i --ip", "Source IP (IPv4 or IPv6)."):default("10.0.0.1")
	parser:option("-d --destination", "Destination IP (IPv4 or IPv6).")
	parser:option("-f --flows", "Number of different IPs to use."):default(100):convert(tonumber)
	parser:option("-s --synq", "Number of SYN queues."):default(0):convert(tonumber)
	parser:option("-x --synackq", "Number of SYN-ACK queues."):default(0):convert(tonumber)
	parser:option("-a --ackq", "Number of ACK queues."):default(0):convert(tonumber)
	parser:flag("-c", "Add RX counter.")
	parser:option("-m --ethDst", "Destination MAC, this option may be repeated."):count("*"):convert(convertMac_fake)
	parser:option("--ipg", "Inter-packet gap, time units (s, ms, us) must be specified."):convert(convertTime)
end

function master(args)
	if args.synq == 0 and args.ackq == 0 and args.synackq == 0 and not args.c then
		log:fatal("Use at least one queue")
	end

	local txQueues = args.synq + args.ackq + args.synackq
	local rxQueues = args.ackq + args.synackq
	if args.c then rxQueues = rxQueues + 1 end

	for i, dev in ipairs(args.dev) do
		if rxQueues == 0 then rxQueues = 1 end
		if txQueues == 0 then txQueues = 1 end
		local dev = device.config{port = dev, txQueues = txQueues, rxQueues = rxQueues, rssQueues = rxQueues}
		dev:wait()

		for i = 0, args.ackq-1 do
			local txQ = dev:getTxQueue(i)
			txQ:setRate(args.rate)
			mg.startTask("replySlave", false, dev, i)
		end

		for i = args.ackq, args.ackq+args.synackq-1 do
			local txQ = dev:getTxQueue(i)
			txQ:setRate(args.rate)
			mg.startTask("replySlave", true, dev, i)
		end

		for i = args.ackq+args.synackq, args.ackq+args.synackq+args.synq-1 do
			local txQ = dev:getTxQueue(i)
			txQ:setRate(args.rate)
			mg.startTask("synSlave", txQ, args.ip, args.flows, args.destination, args.ethDst, args.ipg)
		end

		if args.c then
			mg.startTask("rxCount", dev, rxQueues-1)
		end
	end
	mg.waitForTasks()
end

local zero16 = hton16(0)

function replySlave(synack, dev, qin)
	if synack then
		print("replySlave synack")
	else
		print("replySlave -")
	end
	local txQ = dev:getTxQueue(qin)
	local rxQ = dev:getRxQueue(qin)
	local txBufs = memory.bufArray(128)
	local rxBufs = memory.bufArray(128)
	local txStats = stats:newDevTxCounter(txQ, "plain")
	local rxStats = stats:newDevRxCounter(rxQ, "plain")

	while mg.running() do
		local tx = 0
		local rx = rxQ:recv(rxBufs)
		for i = 1, rx do
			local buf = rxBufs[i]
			-- alter buf
			local pkt = buf:getTcpPacket(ipv4)
			if pkt.ip4:getProtocol() == ip4.PROTO_TCP and
				pkt.tcp:getSyn() and
				(pkt.tcp:getAck() or synack)
			then
				-- print(string.format("RECV %d %d\n", rx, tx))
				local seq = pkt.tcp:getSeqNumber()
				local ack = pkt.tcp:getAckNumber()

				if synack then
					pkt.tcp:setAck()
					pkt.tcp:setAckNumber(seq+1)
					pkt.tcp:setSeqNumber(ack)
				else
					pkt.tcp:unsetSyn()
					pkt.tcp:setAckNumber(seq+1)
					pkt.tcp:setSeqNumber(ack)
				end

				local tmp = pkt.ip4.src:get()
				pkt.ip4.src:set(pkt.ip4.dst:get())
				pkt.ip4.dst:set(tmp)

				local tmp1 = pkt.eth.dst:get()
				pkt.eth.dst:set(pkt.eth.src:get())
				pkt.eth.src:set(tmp1)

				local tmp2 = pkt.tcp:getDstPort()
				pkt.tcp:setDstPort(pkt.tcp:getSrcPort())
				pkt.tcp:setSrcPort(tmp2)

				--pkt.ip4:setChecksum(0)
				pkt.ip4.cs = zero16 -- FIXME: setChecksum() is extremely slow

				tx = tx + 1
				txBufs[tx] = buf
			end
		end
		rxBufs:freeAfter(rx)
		if tx > 0 then
			txBufs:resize(tx)
			--offload checksums to NIC
			txBufs:offloadTcpChecksums(ipv4)
			txQ:send(txBufs)

			rxStats:update()
			txStats:update()
		end
	end
	rxStats:finalize()
	txStats:finalize()
end

function synSlave(queue, minA, numIPs, dest, ethDst_str, ipg)
	ethDst = {}
	for i,x in ipairs(ethDst_str) do
		ethDst[i] = parseMacAddress(x, true)
	end

	local ipgSleepFunc = function() end
	if ipg and ipg.n ~= 0 then
		if ipg.unit == "us" then
			ipgSleepFunc = function() libmoon.sleepMicrosIdle(ipg.n) end
		elseif ipg.unit == "ms" then
			ipgSleepFunc = function() libmoon.sleepMillisIdle(ipg.n) end
		elseif ipg.unit == "s" then
			ipgSleepFunc = function() libmoon.sleepMillisIdle(ipg.n * 1000) end
		end
	end

	--- parse and check ip addresses
	local minIP, ipv4 = parseIPAddress(minA)
	if minIP then
		log:info("Detected an %s address.", minIP and "IPv4" or "IPv6")
	else
		log:fatal("Invalid minIP: %s", minA)
	end

	-- min TCP packet size for IPv6 is 74 bytes (+ CRC)
	local packetLen = ipv4 and 60 or 74
	
	local mem = memory.createMemPool(function(buf)
		buf:getTcpPacket(ipv4):fill{ 
			ethSrc = queue,
			ethDst = "90:e2:ba:7d:85:6c",
			ip4Dst = dest, 
			ip6Dst = dest,
			tcpSyn = 1,
			tcpSeqNumber = 1,
			tcpWindow = 10,
			pktLength = packetLen}
		-- FIXME: workaround
		if ethDst[1] then
			buf:getTcpPacket(ipv4).eth:setDst(ethDst[1])
		end
	end)

	local updateEthDst = function(pkt) end
	if #ethDst > 1 then
		local idx = nil
		local dst
		updateEthDst = function(pkt)
			idx, dst = next(ethDst, idx)
			if not idx then
				idx = nil
				idx, dst = next(ethDst, idx)
			end
			pkt.eth:setDst(dst)
		end
	end

	local bufs = mem:bufArray(128)
	local counter = 0
	local portCounter = 0
	local c = 0

	local txStats = stats:newDevTxCounter(queue, "plain")
	while mg.running() do
		-- fill packets and set their size
		bufs:alloc(packetLen)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getTcpPacket(ipv4)

			pkt.tcp:setDstPort(80)
			pkt.ip4.src:set(minIP)
			updateEthDst(pkt)
			--increment IP
			if ipv4 then
				   pkt.ip4.src:set(minIP)
				   pkt.ip4.src:add(counter)
			else
				   pkt.ip6.src:set(minIP)
				   pkt.ip6.src:add(counter)
			end
			counter = incAndWrap(counter, numIPs)

			pkt.tcp:setSrcPort(1000+portCounter)
			portCounter = incAndWrap(portCounter, 100)

			-- dump first 3 packets
			if c < 3 then
				buf:dump()
				c = c + 1
			end
		end
		--offload checksums to NIC
		bufs:offloadTcpChecksums(ipv4)

		queue:send(bufs)
		txStats:update()
		ipgSleepFunc()
	end
	txStats:finalize()
end

function pcap_replay(queue, file, loop)
	if not file then
		log:fatal("pcap_replay: source PCAP file must be set via --file")
	end
	local txStats = stats:newDevTxCounter(queue, "plain")
	local mempool = memory:createMemPool()
	local bufs = mempool:bufArray(256)
	local pcapFile = pcap:newReader(file)
	while mg.running() do
		local n = pcapFile:read(bufs)
		if n == 0 then
			if loop then
				pcapFile:reset()
			else
				break
			end
		end
		bufs:resize(n)
		bufs:offloadTcpChecksums(ipv4)
		queue:send(bufs)
		txStats:update()
	end
	txStats:finalize()
end

function rxCount(dev, qid)
	print("rxCount")
	local rxQ = dev:getRxQueue(qid)
	local rxCtr = stats:newDevRxCounter(rxQ)
	local rxBufs = memory.bufArray(128)
	while mg.running() do
		local rx = rxQ:recv(rxBufs)
		rxBufs:freeAll()
		rxCtr:update()
	end
	rxCtr:finalize()
end

defaults = {rx_queues = 0, tx_queues = 1}

function task(taskNum, txInfo, rxInfo, args)
	local txQ = txInfo[1].queue
	synSlave(txQ, args.ip, args.flows, args.destination, args.ethDst, args.ipg)
end
