local mg		= require "moongen"
local memory	= require "memory"
local stats		= require "stats"
local log		= require "log"
local ip4		= require "proto.ip4"
local libmoon	= require "libmoon"

defaults = {rx_queues = 0, tx_queues = 1}

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

	parser:description("Generates TCP SYN flood from varying source IPs")
	parser:option("--ipSrc", "Initial source IP."):default("10.0.0.1")
	parser:option("--ipDst", "Destination IP.")
	parser:option("-f --flows", "Number of different IPs to use."):default(100):convert(tonumber)
	parser:option("-m --ethDst", "Destination MAC, this option may be repeated."):count("*"):convert(convertMac_fake)
end

function task(taskNum, txInfo, rxInfo, args)
	local txQ = txInfo[1].queue
	local minA, numIPs, dest, ethDst_str, ipg = args.ipSrc, args.flows, args.ipDst, args.ethDst, args.ipg
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
			ethSrc = txQ,
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

	local bufs = mem:bufArray(args.tx_buf)
	local counter = 0
	local portCounter = 0
	local c = 0

	local txStats = stats:newDevTxCounter(txQ, "plain")
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

		txQ:send(bufs)
		txStats:update()
		ipgSleepFunc()
	end
	txStats:finalize()
end
