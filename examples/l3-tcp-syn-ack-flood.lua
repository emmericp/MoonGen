local mg		= require "moongen"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local log 		= require "log"
local ip4		= require "proto.ip4"
local libmoon	= require "libmoon"


function configure(parser)
	function convertMac(str)
		mac = parseMacAddress(str, true)
		if not mac then
			parser:error("failed to parse MAC "..str)
		end
		return mac
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
	parser:option("-m --ethDst", "Destination MAC, this option may be repeated."):count("*"):convert(convertMac)
	parser:option("--ipg", "Inter-packet gap, time units (s, ms, us) must be specified."):convert(convertTime)
end

function master(args)
	if args.synq == 0 and args.ackq == 0 and args.synackq == 0 then
		log:fatal("Use at least one queue")
	end

	local txQueues = args.synq + args.ackq + args.synackq
	local rxQueues = args.ackq + args.synackq

	for i, dev in ipairs(args.dev) do
		if rxQueues == 0 then rxQueues = 1 end
		local dev = device.config{port = dev, txQueues = txQueues, rxQueues = rxQueues}
		dev:wait()

		for i = 0, args.ackq-1 do
		   local txQ = dev:getTxQueue(i)
		   local rxQ = dev:getRxQueue(i)
		   txQ:setRate(args.rate)
		   mg.startTask("replySlave", false, txQ, rxQ)
		end

		for i = args.ackq, args.ackq+args.synackq-1 do
		   local txQ = dev:getTxQueue(i)
		   local rxQ = dev:getRxQueue(i)
		   txQ:setRate(args.rate)
		   mg.startTask("replySlave", true, txQ, rxQ)
		end

		for i = args.ackq+args.synackq, args.ackq+args.synackq+args.synq-1 do
		   local txQ = dev:getTxQueue(i)
		   txQ:setRate(args.rate)
		   mg.startTask("synSlave", txQ, args.ip, args.flows, args.destination, args.ethDst, args.ipg)
		end

	end
	mg.waitForTasks()
end

function replySlave(synack, txQ, rxQ)
	if synack then
		print("replySlave synack")
	else
		print("replySlave -")
	end
	local txBufs = memory.bufArray(128)
	local rxBufs = memory.bufArray(128)
	local txStats = stats:newDevTxCounter(txQ, "plain")
	local rxStats = stats:newDevRxCounter(rxQ, "plain")

	while mg.running() do
		local rx = rxQ:recv(rxBufs)
		local tx = 0
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

				tx = tx + 1
				txBufs[tx] = buf
			end
		end
		if tx > 0 then
			txBufs:resize(tx)
			--offload checksums to NIC
			txBufs:offloadTcpChecksums(ipv4) -- FIXME
			txQ:send(txBufs)
			--txQ:sendN(txBufs, tx)

			--bufs:freeAll()
			rxStats:update()
			txStats:update()
		end
	end
	rxStats:finalize()
	txStats:finalize()
end

function synSlave(queue, minA, numIPs, dest, ethDst, ipg)
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
			ethDst = ethDst[1] or "90:e2:ba:7d:85:6c",
			ip4Dst = dest, 
			ip6Dst = dest,
			tcpSyn = 1,
			tcpSeqNumber = 1,
			tcpWindow = 10,
			pktLength = packetLen
		}
	end)

	if #ethDst == 0 or #ethDst == 1 then
		function updateEthDst(pkt)
		end
	else
		local idx = nil
		function updateEthDst(pkt)
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
	while true do
		if mg.running() then
			-- fill packets and set their size
			bufs:alloc(packetLen)
			for i, buf in ipairs(bufs) do
				local pkt = buf:getTcpPacket(ipv4)

				pkt.tcp:setDstPort(80)
				pkt.ip4.src:set(minIP)
				updateEthDst(pkt)
				--increment IP
				-- if ipv4 then
				--	   pkt.ip4.src:set(minIP)
				--	   pkt.ip4.src:add(counter)
				-- else
				--	   pkt.ip6.src:set(minIP)
				--	   pkt.ip6.src:add(counter)
				-- end
				-- counter = incAndWrap(counter, numIPs)

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
		end
		ipgSleepFunc()
	end
	txStats:finalize()
end

