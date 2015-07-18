local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"


function master(txPorts, minIp, numIps, rate)
	if not txPorts then
		printf("usage: txPort1[,txPort2[,...]] [minIP numIPs rate]")
		return
	end
	minIp = minIp or "10.0.0.1"
	numIps = numIps or 100
	rate = rate or 0
	for currentTxPort in txPorts:gmatch("(%d+),?") do
		currentTxPort = tonumber(currentTxPort) 
		local txDev = device.config({ port = currentTxPort })
		txDev:wait()
		txDev:getTxQueue(0):setRate(rate)
		dpdk.launchLua("loadSlave", currentTxPort, 0, minIp, numIps)
	end
	dpdk.waitForSlaves()
end

function loadSlave(port, queue, minA, numIPs)
	--- parse and check ip addresses

	local minIP, ipv4 = parseIPAddress(minA)
	if minIP then
		printf("INFO: Detected an %s address.", minIP and "IPv4" or "IPv6")
	else
		errorf("ERROR: Invalid minIP: %s", minA)
	end

	-- min TCP packet size for IPv6 is 74 bytes (+ CRC)
	local packetLen = ipv4 and 60 or 74
	
	--continue normally
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getTcpPacket(ipv4):fill{ 
			ethSrc="90:e2:ba:2c:cb:02", ethDst="90:e2:ba:35:b5:81", 
			ip4Dst="192.168.1.1", 
			ip6Dst="fd06::1",
			tcpSyn=1,
			tcpSeqNumber=1,
			tcpWindow=10,
			pktLength=packetLen }
	end)

	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(128)
	local counter = 0
	local c = 0

	local txStats = stats:newDevTxCounter(queue, "plain")
	while dpdk.running() do
		-- faill packets and set their size 
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
		
		totalSent = totalSent + queue:send(bufs)
		txStats:update()
	end
	txStats:finalize()
end


