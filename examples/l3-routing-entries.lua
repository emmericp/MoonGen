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
	local rate = 10000
	local ipv6 = false
	local packetLen = 64
	local sIp = "192.168.1.1"
	local sMac = "90:e2:ba:2c:cb:02"	--klaipeda eth-test1
	local dMac = "90:e2:ba:35:b5:81"	--tartu eth-test1
	for i = 1, #args do
		if 	args[i] == "-br" then 	rate = tonumber(args[i + 1]); i = i + 1
		elseif 	args[i] == "-pr" then 	rate = tonumber(args[i + 1]) * 8 * packetLen; i = i + 1
		elseif 	args[i] == "-6"  then	  ipv6 = true
		elseif 	args[i] == "-l"	 then	  packetLen = tonumber(args[i + 1]); i = i + 1
		elseif  args[i] == "-s"  then   sIp = args[i + 1]; i = i + 1
		elseif	args[i] == "-sm" then   sMac = args[i + 1]; i = i + 1
		elseif	args[i] == "-dm" then   dMac = args[i + 1]; i = i + 1
		end
	end
	
	print(txPort, minIp, maxIp, rate, ipv6, packetLen, sIp, sMac, dMac)
	if not txPort or not minIp or not maxIp then
		printf("usage: %s txPort minIp maxIp [-br bit-rate] [-pr packet-rate] [-6 IPv6] [-s source IP] [-sm source MAC] [-dm destination MAC]", arg[0])
		return
	end

	local rxMempool = memory.createMemPool()
	local txDev = device.config(txPort, rxMempool, 2, 2)
	txDev:wait()
	txDev:getTxQueue(0):setRate(rate)
	dpdk.launchLua("loadSlave", txPort, 0, packetLen, minIp, maxIp, ipv6, sIp, sMac, dMac)
	dpdk.waitForSlaves()
end

function insertInTable(...)
	local table = {}
	for i = 1, select('#', ...) do
		table[i] = select(i, ...)
		if table[i] == nil then table[i] = 0 end
		table[i] = tonumber(table[i], 16)
	end
	return table
end

function loadSlave(port, queue, packetLen, minIp, maxIp, ipv6, sIp, sMac, dMac)
	--parse and check ip range
	local A1, B1, C1, D1
	local A2, B2, C2, D2
	local a, b, c, d
	local minA = {}
	local maxA = {}
	local curA = {}
	local srcIp = {}
	local srcMac = {}
	local dstMac = {}

	--parse and check MACs
	srcMac = insertInTable(string.match(sMac, '(%x%x):(%x%x):(%x%x):(%x%x):(%x%x):(%x%x)'))
	dstMac = insertInTable(string.match(dMac, '(%x%x):(%x%x):(%x%x):(%x%x):(%x%x):(%x%x)'))

	--parse and check ip range
	if ipv6 then --CURRENTLY NOT WORKING
		minA = insertInTable(string.match(minIp, '(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x)'))
		maxA = insertInTable(string.match(maxIp, '(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x)'))
		for i = 1, 16 do
			if minA[i] == nil then
				printf("Invalid minIp")
				return
			end
			if maxA[i] == nil then
				printf("Invalid maxIp")
				return
			end

			curA[i] = minA[i]
			printf('%2x %2x', minA[i], maxA[i])
		end		
	else	--ipv4 address
		--source
		srcIp = insertInTable(string.match(sIp, '(%d+).(%d+).(%d+).(%d+)'))

		--dest. ranges
		A1, B1, C1, D1 = tonumberall(string.match(minIp, '(%d+).(%d+).(%d+).(%d+)'))
		if A1 == nil or B1 == nil or C1 == nil or D1 == nil or 
			A1 > 255 or B1 > 255 or C1 > 255 or D1 > 255 then 
			printf("Invalid minIp %s ", minIp)
			return
		end
	
		A2, B2, C2, D2 = tonumberall(string.match(maxIp, '(%d+).(%d+).(%d+).(%d+)'))
		if A2 == nil or B2 == nil or C2 == nil or D2 == nil or 
			A2 > 255 or B2 > 255 or C2 > 255 or D2 > 255 then 
			printf("Invalid maxIp %s ", minIp)
			return
		end

		for i = 1, 4 do printf("%2x %2x %2x", srcMac[i], dstMac[i], srcIp[i]) end
		for i = 5, 6 do printf("%2x %2x", srcMac[i], dstMac[i]) end
		print(A1, B1, C1, D1)
		print(A2, B2, C2, D2)

		--TODO check min ip < max ip
		--first ip = min_ip
		a = A1
		b = B1
		c = C1
		d = D1
	end

	--continue normally
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		local p = ffi.cast("struct packet*", buf.pkt.data)
		-- ethernet header

		for i = 0, 5 do
			p.eth_h.src.byte[i] = srcMac[i + 1]		-- src MAC
			p.eth_h.dst.byte[i] = dstMac[i + 1]		-- dst MAC
		end                     
		if ipv6 then						-- ethertype
			p.eth_h.ethertype = hton16(0x86dd)		-- ipv6
		else
			p.eth_h.ethertype = hton16(0x0800) 		-- ipv4
		end

		--ip header
		if ipv6 then
			--ipv6 header 
			p.ipv6_h.vtf		  = 96				              -- hardcoded 0x6000 0000
			p.ipv6_h.len		  = hton16(packetLen - 54)	-- packet length - (eth_h(14) + ipv6_h(40))
			p.ipv6_h.nexthdr	= 0x11				            -- UDP
			p.ipv6_h.ttl	  	= 64

			for i = 0, 16 do
				p.ipv6_h.src.byte[i]	= 0xa0 + i
				p.ipv6_h.dst.byte[i]	= 0xf0 + i
			end
		else
			--ipv4  header
			p.ipv4_h.verihl		= 0x45  			              -- hardcoded version (4bit: 4) + ihl (4bit: 5)
			p.ipv4_h.tos 		  = 0				                  -- not needed
			p.ipv4_h.len	 	  = hton16(packetLen - 14)  	-- packet length - ethernet header(14)
			p.ipv4_h.id		    = hton16(2012)			        -- not needed
			p.ipv4_h.fragOff	= 0				                  -- not needed
			p.ipv4_h.ttl		  = 64				                -- standart ttl
			p.ipv4_h.protocol	= 0x11 				              -- next header: UDP
			p.ipv4_h.check		= 0				                  -- calculated later
			for i = 0, 3 do
				p.ipv4_h.src.byte[i] = srcIp[i + 1]		      -- src IP
			end
			p.ipv4_h.dst.addr	= 0xffffffff 			          -- dst IP set later
		end


		--udp header
		p.udp_h.src		  = hton16(1116)				      -- src port
		p.udp_h.dst		  = hton16(2222)				      -- dst port
		p.udp_h.len  		= hton16(packetLen - 34)		-- packet length - (ethernet(14) + ip header(20))
		
		if ipv6 then --TODO mandatory checksum for ipv6 +udp?!
		else
			p.udp_h.check		= 0					      -- optional checksum; 0 = not used
		end
--[[
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		for i = 0, 63, 1 do
			printf("Byte %2d: %2x", i, data[i])
		end	
		exit(0) --]]	
	end)

	local BURST_SIZE = 31
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
		-- TODO: enable Lua 5.2 features in luajit and use __ipairs and/or __len metamethod on bufarrays
		for i = 0, BURST_SIZE - 1 do
			if ipv6 then --CURRENTLY NOT WORKING
				local p = ffi.cast("struct packet *", bufs.array[i].pkt.data)
				hitMaxIp = true
				--assign ip
				for b = 1, 16 do
					p.ipv6_h.dst.byte[b - 1] = curA[b]
					
					--check if maxIp is hit (if one is not -> false -> dont reset)
					if not (curA[b] == maxA[b]) then
						hitMaxIp = false
					end
				end

				--hit maxIp -> reset to minIp, otherwise increment
				if hitMaxIp then
					for b = 1, 16 do
						curA[b] = minA[b]
					end
				else
					for b = 16, 1, -1 do
						if curA[b] == 0xFF then --set to 0 and inc next byte
							curA[b] = 0x0
							--continue
						else
							curA[b] = curA[b] + 1
							break
						end
					end
				end

--[[        
			        local data = ffi.cast("uint8_t*", bufs.array[i].pkt.data)                 
			        for i = 0, 63, 1 do                                             
			            printf("Byte %2d: %2x", i, data[i])                     
			        end                                             
                                exit(0)--]]
			else
				local p = ffi.cast("struct packet *", bufs.array[i].pkt.data)
				p.ipv4_h.dst.byte[0] = a
				p.ipv4_h.dst.byte[1] = b
				p.ipv4_h.dst.byte[2] = c
				p.ipv4_h.dst.byte[3] = d

				bufs.array[i].pkt.pkt_len = packetLen
				bufs.array[i].pkt.data_len = packetLen
	
				--hit max_ip -> reset to min_ip, otherwise increment ip
				if a == A2 and b == B2 and c == C2 and d == D2 then
					a = A1
					b = B1
					c = C1
					d = D1
				else  
					d = d + 1
					--check possible overflows
					if d == 256 then
						d = 0
						c = c + 1
						if c == 256 then
							c = 0
							b = b + 1
							if b == 256 then
								b = 0
								a = a + 1
							end
						end
					end
				end
	
				--calculate checksum
				p.ipv4_h.check = 0 --reset as packets can be reused
				p.ipv4_h.check = checksum(p.ipv4_h, 20) --]]  
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


