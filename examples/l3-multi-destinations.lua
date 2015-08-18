--- Send UDPv4/v6 packets with <numIPs> different destination IPv4/v6 addresses
-- <minIP> decides whether it's IPv4 or IPv6
-- starts sending with <minIP>, increases IP by one for each packet (until <numIPs> reached, restart with <minIP>)
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"
local utils 	= require "utils"
local headers	= require "headers"
local packet	= require "packet"

local ffi	= require "ffi"

function master(txPort, minIP, numIPs, rate)
	
	if not txPort or not minIP or not numIPs or not rate then
		printf("usage: txPort minIP numIPs rate")
		return
	end

	local txDev = device.config(txPort)
	device.waitForLinks()

	txDev:getTxQueue(0):setRate(rate)

	dpdk.launchLua("loadSlave", txDev, txDev:getTxQueue(0), minIP, numIPs)
	dpdk.waitForSlaves()
end

function loadSlave(dev, queue, minA, numIPs)
	--- parse and check ip addresses
	-- min UDP packet size for IPv6 is 66 bytes
	-- 4 bytes subtracted as the CRC gets appended by the NIC
	local packetLen = 66 - 4

	local minIP, ipv4 = parseIPAddress(minA)
	if minIP then
		printf("INFO: Detected an %s address.", ipv4 and "IPv4" or "IPv6")
	else
		errorf("Invalid minIP: %s", minA)
	end

	-- prefill buffers
	local mem = memory.createMemPool(function(buf)
		local pkt = buf:getUdpPacket(ipv4):fill{ 
			ethSrc="90:e2:ba:2c:cb:02", ethDst="90:e2:ba:35:b5:81", 
			ip4Src="192.168.1.1", 
			ip6Src="fd06::1",
			-- the destination address will be set for each packet individually (see below)
			pktLength=packetLen 
		}
	end)

	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(128)
	local counter = 0
	local c = 0

	print("Start sending...")
	while dpdk.running() do
		-- allocate packets and set their size 
		bufs:alloc(packetLen)
		for i, buf in ipairs(bufs) do 			
			local pkt = buf:getUdpPacket(ipv4)
			
			-- increment IP
			if ipv4 then
				pkt.ip4:setDst(minIP)
				pkt.ip4.dst:add(counter)
			else
				pkt.ip6:setDst(minIP)
				pkt.ip6.dst:add(counter)
			end
			counter = incAndWrap(counter, numIPs)

			-- dump first few packets to see what we send
			if c < 3 then
				buf:dump()
				c = c + 1
			end
		end 
		-- offload checksums to NIC
		bufs:offloadUdpChecksums(ipv4)
		
		-- send packets
		totalSent = totalSent + queue:send(bufs)
		
		-- print statistics
		local time = dpdk.getTime()
		if time - lastPrint > 0.1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("%.5f %d", time - lastPrint, totalSent - lastTotal)	-- packet_counter-like output
			--printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end


