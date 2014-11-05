local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"
local utils 	= require "utils"
local headers	= require "headers"

local ffi	= require "ffi"

function master(...)
	local args = {...}
	--parse args
	local txPort = tonumber((select(1, ...)))
	local minIp = select(2, ...)
	local maxIp = select(3, ...)
	local rate = select(4, ...)
	
	if not txPort or not minIp or not maxIp or not rate then
		printf("usage: %s txPort minIp maxIp rate", arg[0])
		return
	end

	local rxMempool = memory.createMemPool()
	local txDev = device.config(txPort, rxMempool, 2, 2)
	txDev:wait()
	txDev:getTxQueue(0):setRate(rate)
	dpdk.launchLua("loadSlave", txPort, 0, minIp, maxIp)
	dpdk.waitForSlaves()
end

function loadSlave(port, queue, minIp, maxIp)
	--- parse and check ip addresses
	local numIPs
	local packetLen = 64
	local ipv4 = true

	-- first check if its an ipv4 address
	minIP = parseIPAddress(minIP)
	maxIP = parseIPAddress(maxIP)
	
	if minIP == nil or maxIP == nil then
		printf("Addresses are not IPv4, checking for IPv6...")
		ipv4 = false
	end

	-- if not an ipv4 address, check if its ipv6
	if not ipv4 then
		minIP = parseIP6Address(minIP)
		maxIP = parseIP6Address(maxIP)
		
		if minIP == nil or maxIP == nil then
			printf("Addresses are not IPv6, stopping now.")
			return
		end
	end
	
	-- calculate how many addresses
	numIPs = (maxIP - minIP) + 1

	--continue normally
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		local pkt
		if ipv4 then
			pkt = buf:getUDPPacket()
		else 
			pkt = buf:getUDP6Packet()
		end
		
		pkt.pkt_len = packetLen
		pkt.data_len = packetLen
		
		--ethernet header
		pkt.eth.dst[0] = 0x90 --tartu eth-test1
		pkt.eth.dst[1] = 0xe2
		pkt.eth.dst[2] = 0xba
		pkt.eth.dst[3] = 0x35
		pkt.eth.dst[4] = 0xb5
		pkt.eth.dst[5] = 0x81
		pkt.eth.src[0] = 0x90 --klaipeda eth-test1
		pkt.eth.src[1] = 0xe2
		pkt.eth.src[2] = 0xba
		pkt.eth.src[3] = 0x2c
		pkt.eth.src[4] = 0xcb
		pkt.eth.src[5] = 0x02
		if ipv4 then
			pkt.eth.type = hton16(0x0800)
		else
			pkt.eth.type = hton16(0x86dd)
		end
		
		--ip header
		if ipv4 then
			pkt.ip.verihl = 0x45
			pkt.ip.tos = 0
			pkt.ip.len = hton16(packetLen - 14)
			pkt.ip.id = hton16(2012)
			pkt.ip.frag = 0
			pkt.ip.ttl = 64
			pkt.ip.protocol = 0x11
			pkt.ip.cs = 0
			pkt.ip.src.uint8[0] = 192
			pkt.ip.src.uint8[1] = 168
			pkt.ip.src.uint8[2] = 1
			pkt.ip.src.uint8[3] = 1
			pkt.ip.dst.uint32 = 0xffffffff 
		else --ipv6
			pkt.ip.vtf = 96
			pkt.ip.len = hton16(packetLen - 54)
			pkt.ip.nexthdr = 0x11
			pkt.ip.ttl = 64
			pkt.ip.src.uint64[0] = 0
			pkt.ip.src.uint8[0] = 0xfd
			pkt.ip.src.uint8[1] = 0x06
			pkt.ip.src.uint64[1] = 1
			pkt.ip.dst.uint64[0] = 0
			pkt.ip.dst.uint64[1] = 0
		end
		
		--udp header
		pkt.udp.src	= hton16(1116)
		pkt.udp.dst	= hton16(2222)
		pkt.udp.len = hton16(packetLen - 34)
		pkt.udp.check = 0
--[[
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		for i = 0, 63, 1 do
			printf("Byte %2d: %2x", i, data[i])
		end	
		exit(0) --]]	
	end)

	local BURST_SIZE = 1
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(BURST_SIZE)
	local counter = 0
	local cs = 0
	local sum = 0
	local carry = 0
	local hitMaxIp = false

	print("Start sending...")
	while dpdk.running() do
		bufs:fill(60)
		for i, buf in ipairs(bufs) do
			local pkt
			local ip_bytes
			
			if ipv4 then
				pkt = buf:getUDPPacket()
			else
				pkt = buf:getUDPV6Packet()
			end
			
			pkt.ip.dst:set(minIP + counter)
			counter = (counter + 1) % numIPs
		
			--calculate checksum
			if ipv4 then
				--pkt.ip.cs = 0 --reset as packets can be reused
				--pkt.ip.cs = checksum(pkt.ip, 20)
				pkt.ip:calculateChecksum()
			else
				--TODO UDP checksum for IPv6 is mandatory
				pkt.udp.check = 0
			end
		end
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 0.1 then 	--counter frequency
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("%.5f %d", time - lastPrint, totalSent - lastTotal)	-- packet_counter-like output
			--printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end


