local mg		= require "moongen"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local log 		= require "log"

function configure(parser)
	parser:description("Generates TCP SYN flood from varying source IPs, supports both IPv4 and IPv6")
	parser:argument("dev", "Devices to transmit from."):args("*"):convert(tonumber)
	parser:option("-r --rate", "Transmit rate in Mbit/s."):default(10000):convert(tonumber)
	parser:option("-i --ip", "Source IP (IPv4 or IPv6)."):default("10.0.0.1")
	parser:option("-d --destination", "Destination IP (IPv4 or IPv6).")
	parser:option("-f --flows", "Number of different IPs to use."):default(100):convert(tonumber)
end

function master(args)
	for i, dev in ipairs(args.dev) do
		local dev = device.config{port = dev}
		dev:wait()
		dev:getTxQueue(0):setRate(args.rate)
		mg.startTask("loadSlave", dev:getTxQueue(0), args.ip, args.flows, args.destination)
	end
	mg.waitForTasks()
end

function loadSlave(queue, minA, numIPs, dest)
	--- parse and check ip addresses
	local minIP, ipv4 = parseIPAddress(minA)
	if minIP then
		log:info("Detected an %s address.", minIP and "IPv4" or "IPv6")
	else
		log:fatal("Invalid minIP: %s", minA)
	end

	-- min TCP packet size for IPv6 is 74 bytes (+ CRC)
	local packetLen = ipv4 and 60 or 74
	
	-- continue normally
	local mem = memory.createMemPool(function(buf)
		buf:getTcpPacket(ipv4):fill{ 
			ethSrc = queue,
			ethDst = "12:34:56:78:90",
			ip4Dst = dest, 
			ip6Dst = dest,
			tcpSyn = 1,
			tcpSeqNumber = 1,
			tcpWindow = 10,
			pktLength = packetLen
		}
	end)

	local bufs = mem:bufArray(128)
	local counter = 0
	local c = 0

	local txStats = stats:newDevTxCounter(queue, "plain")
	while mg.running() do
		-- fill packets and set their size 
		bufs:alloc(packetLen)
		for i, buf in ipairs(bufs) do 			
			local pkt = buf:getTcpPacket(ipv4)
			
			--increment IP
			if ipv4 then
				pkt.ip4.src:set(minIP)
				pkt.ip4.src:add(counter)
			else
				pkt.ip6.src:set(minIP)
				pkt.ip6.src:add(counter)
			end
			counter = incAndWrap(counter, numIPs)

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
	txStats:finalize()
end

