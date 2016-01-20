local mg	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats	= require "stats"
local proto	= require "proto.proto"
local log 	= require "log"
local ffi 	= require "ffi"

function master(txPort, rxPort, isEndpoint, isTunneled, rate)
	if not txPort or not rxPort or not isEndpoint or not isTunneled then
		log:info("usage: txPort rxPort isEndpoint isTunneled [rate]")
		return
	end
	txPort = tonumber(txPort)
	rxPort = tonumber(rxPort)
	isEndpoint = tonumber(isEndpoint) == 1
	isTunneled= tonumber(isTunneled) == 1
	rate = rate or 0

	local txDev = device.config{ port = txPort }
	txDev:wait()
	txDev:getTxQueue(0):setRate(rate)
	local rxDev = device.config{ port = rxPort }
	rxDev:wait()

	if isEndpoint then
		if isTunneled then
			mg.launchLua("decapsulateSlave", rxDev, txPort, 0)
		else
			mg.launchLua("encapsulateSlave", rxDev, txPort, 0)
		end
	else
		mg.launchLua("loadSlave", isTunneled, txPort, 0)
		mg.launchLua("counterSlave", isTunneled, rxDev)
	end

	mg.waitForSlaves()
end

-- vtep is the endpoint when MoonGen de-/encapsulates traffic 
-- enc is facing the l3 network, dec is facing l2 network
-- remote is where we tx/rx traffic with MoonGen (load-/counterslave)
local encVtepEth 	= "90:e2:ba:2c:cb:02" -- vtep, public/l3 side
local encVtepIP		= "10.0.0.1"
local encRemoteEth	= "90:e2:ba:01:02:03" -- MoonGen load/counter slave
local encRemoteIP	= "10.0.0.2"

local decVtepEth	= "90:e2:ba:1f:8d:44" -- vtep, provate/l2 side
local decRemoteEth	= "90:e2:ba:0a:0b:0c" -- MoonGen counter/load slave

-- can be any proper payload really, we use this to identify the packets
local decEthType 	= 1

local decPacketLen	= 60
local encapsulationLen	= 14 + 20 + 8 + 8
local encPacketLen 	= encapsulationLen + decPacketLen

function loadSlave(sendTunneled, port, queue)

	local queue = device.get(port):getTxQueue(queue)
	local packetLen
	local mem

	if sendTunneled then
		-- create a with VXLAN encapsulated ethernet packet
		packetLen = encPacketLen
		mem = memory.createMemPool(function(buf)
			buf:getVxlanPacket():fill{ 
				ethSrc=encRemoteEth, 
				ethDst=encVtepEth, 
				ip4Src=encRemoteIP,
				ip4Dst=encVtepIP,

				vxlanReserved2=0xf,
				vxlanVNI=1000,

				innerEthSrc=decVtepEth,
				innerEthDst=decRemoteEth,
				innerEthType=decEthType,

				pktLength=encPacketLen 
			}
		end)
	else
		-- create an ethernet packet
		packetLen = decPacketLen
		mem = memory.createMemPool(function(buf)
			buf:getEthernetPacket():fill{ 
				ethSrc=decRemoteEth,
				ethDst=decVtepEth,
				ethType=decEthType,

				pktLength=decPacketLen 
			}
		end)

	end

	local bufs = mem:bufArray()
	local c = 0

	local txStats = stats:newDevTxCounter(queue, "plain")
	while mg.running() do
		-- fill packets and set their size 
		bufs:alloc(packetLen)
		
		-- dump first packet to see what we send
		if c < 1 then
			bufs[1]:dump()
			c = c + 1
		end 
		
		if sendTunneled then
			--offload checksums to NIC
			bufs:offloadUdpChecksums()
		end
		
		queue:send(bufs)
		txStats:update()
	end
	txStats:finalize()
end

function isVxlanPacket(pkt)
	return pkt.eth:getType() == proto.eth.TYPE_IP 
		and pkt.ip4:getProtocol() == proto.ip4.PROTO_UDP 
		and pkt.udp:getDstPort() == proto.udp.PORT_VXLAN
end

function counterSlave(receiveInner, dev)
	rxStats = stats:newDevRxCounter(dev, "plain")
	local bufs = memory.bufArray(1)
	local c = 0

	while mg.running() do
		local rx = dev:getRxQueue(0):recv(bufs)
		if rx > 0 then
			local buf = bufs[1]
			if receiveInner then
				local pkt = buf:getEthernetPacket()
				--if pkt.eth:getSrcString() == decRemoteEth 
				--	and pkt.eth:getDstString() == decVtepEth
				--	and pkt.eth:getType() == decEthType then
					
					if c < 1 then
						printf(red("Received"))
						buf:dump()
						c = c + 1
					end
				--end
			else
				local pkt = buf:getVxlanPacket()
				if isVxlanPacket(pkt) then
					if c < 1 then
						printf(red("Received"))
						buf:dump()
						c = c + 1
					end
				end
			end

			bufs:freeAll()
		end
		rxStats:update()
	end
	rxStats:finalize()
end

function decapsulateSlave(rxDev, txPort, queue)
	local txDev = device.get(txPort)

	local mem = memory.createMemPool(function(buf)
		buf:getRawPacket():fill{ 
			-- we take everything from the received encapsulated packet's payload
		}
	end)
	local rxBufs = memory.bufArray()
	local txBufs = mem:bufArray()
	local c = 0

	local rxStats = stats:newDevRxCounter(rxDev, "plain")
	local txStats = stats:newDevTxCounter(txDev, "plain")
	
	log:info("Starting vtep decapsulation task")

	local rxQ = rxDev:getRxQueue(0)
	local txQ = txDev:getTxQueue(queue)
	while mg.running() do
		local rx = rxQ:tryRecv(rxBufs, 0)
		
		-- alloc empty tx packet
		txBufs:alloc(decPacketLen, 60)
		
		for i = 1, rx do
			local rxBuf = rxBufs[i]
			local rxPkt = rxBuf:getVxlanEncapsulationPacket()
			if isVxlanPacket(rxPkt) then
				-- use template raw packet (empty)
				local txPkt = txBufs[i]:getRawPacket()
			
				-- get the size of only the payload
				local payloadSize = rxBuf:getSize() - encapsulationLen
				
				-- copy payload
				ffi.copy(txPkt.payload, rxPkt.payload, payloadSize)

				-- update buffer size
				txBufs[i]:setSize(payloadSize)
			end
		end
		-- send decapsulated packet
		txQ:sendN(txBufs, rx)                                           
                
		-- free received packet                                         
                rxBufs:free(rx)	
		
		-- update statistics
		rxStats:update()
		txStats:update()
	end
	rxStats:finalize()
	txStats:finalize()
end

function encapsulateSlave(rxDev, txPort, queue)	
	local queue = device.get(txPort):getTxQueue(queue)
	
	local mem = memory.createMemPool(function(buf)
		buf:getVxlanEncapsulationPacket():fill{ 
			-- the outer packet, basically defines the VXLAN tunnel 
			ethSrc=encVtepEth, 
			ethDst=encRemoteEth, 
			ip4Src=encVtepIP,
			ip4Dst=encRemoteIP,
			
			vxlanVNI=1000,}
	end)
	
	local rxBufs = memory.bufArray()
	local c = 0

	local rxStats = stats:newDevRxCounter(rxDev, "plain")
	local txStats = stats:newDevTxCounter(queue, "plain")
	
	log:info("Starting vtep encapsulation task")
	while mg.running() do
		local rx = rxDev:getRxQueue(0):tryRecv(rxBufs, 0)
		local txBufs = mem:bufArray(rx)
		
		-- alloc tx packet with VXLAN template
		txBufs:alloc(encPacketLen)
		
		-- check if we received any packets
		for i = 1, rx do
			-- we encapsulate everything that gets here. One could also parse it as ethernet frame and then only encapsulate on matching src/dst addresses
			local rxPkt = rxBufs[i]:getRawPacket()
			
			-- size of the packet
			local rawSize = rxBufs[i]:getSize()
			
			-- use template VXLAN packet
			local txPkt = txBufs[i]:getVxlanEncapsulationPacket()

			-- copy raw payload (whole frame) to encapsulated packet payload
			ffi.copy(txPkt.payload, rxPkt.payload, rawSize)

			-- update size
			local totalSize = encapsulationLen + rawSize
			-- for the actual buffer
			txBufs[i]:setSize(totalSize)
			-- for the IP/UDP header
			txPkt:setLength(totalSize)
		end
		-- offload checksums
		txBufs:offloadUdpChecksums()

		-- free received packet
		rxBufs:freeAll()

		-- send encapsulated packet
		queue:send(txBufs)
	
		-- update statistics
		txStats:update()
		rxStats:update()
	end
	rxStats:finalize()
	txStats:finalize()
end
