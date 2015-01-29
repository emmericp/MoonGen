local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"
local utils 	= require "utils"
local headers	= require "headers"
local packet	= require "packet"

local arp = require "arp"
local eth = require "ethernet"

local ffi	= require "ffi"

--[[
-- ArpRequester 					ArpResponser
-- 				   arpRequest
-- 				--------------->
--									checks etherType (== ARP),
--										   arpOperation (== Request),
--										   arpIPDst (== devIP)
--
-- 				  arpResponse
-- 				<---------------
--]]

function master(...)
	--parse args
	local reqPort = tonumber((select(1, ...)))
	local resPort = tonumber((select(2, ...)))
	local rate = tonumber(select(3, ...))
	
	if not reqPort or not resPort or not rate then
		printf("usage: reqPort resPort rate")
		return
	end
	
	local reqDev, resDev
	reqDev = device.config(reqPort, memory.createMemPool(), 2, 2)
	resDev = device.config(resPort, memory.createMemPool(), 2, 2)
	device.waitForDevs(reqDev, resDev)		
	
	reqDev:getTxQueue(0):setRate(rate)
	resDev:getTxQueue(0):setRate(rate)
	
	-- resDev:l2Filter(hton16(eth.TYPE_ARP), filter.DROP) -- TODO no idea how any of this works

	--reqPort
	dpdk.launchLua("arpRequesterSlave", reqPort, 0, 0)

	--resPort
	dpdk.launchLua("arpResponderSlave", resPort, 0, 0)
	
	--dpdk.waitForSlaves()
	dpdk.waitForSlaves()
end

function arpRequesterSlave(port, rxQueue, txQueue)
	local packetLen = 64 - 4

	local dev = device.get(port)
	
	local targetIP = "8.8.8.8"
	local devMac = dev:getMac()
	local devIP = "12.34.56.78"
	
	local rxQueue = dev:getRxQueue(rxQueue)
	local txQueue = dev:getTxQueue(txQueue)

	local rxMem = memory.createMemPool()	
	local rxBufs = rxMem:bufArray(1)

	local txMem = memory.createMemPool(function(buf)
		local pkt = buf:getArpPacket():fill{ 
			ethSrc			= devMac, 
			ethDst 			= eth.BROADCAST, 
			
			arpOperation 	= arp.OP_REQUEST,
			arpHardwareSrc 	= devMac,
			arpHardwareDst 	= eth.BROADCAST,
			arpProtoSrc 	= devIP,
			arpProtoDst 	= targetIP,
			
			pktLength = packetLen }
	end)

	local bufs = txMem:bufArray(1)
	local rx
	local c = 0

	print("Start sending...")
	while dpdk.running() do
		if c == 0 then -- only once
			bufs:fill(packetLen)
			for i, buf in ipairs(bufs) do 			
				printf("ArpRequester requested:")
				buf:dump()
			end 
			
			txQueue:send(bufs)
			
			c = 1
		end

		-- receive response
		rx = rxQueue:tryRecv(rxBufs, 10000)
		if rx > 0 then
			printf("ArpRequesterSlave received reply:")
			for i, rxBuf in ipairs(rxBufs) do
				rxBuf:dump()
			end
			dpdk.stop()
		end
	end
end

function arpResponderSlave(port, rxQueue, txQueue)
	local packetLen = 64 - 4

	local dev = device.get(port)
	
	local devMac = dev:getMac()
	local devIP = "8.8.8.8"

	local rxQueue = dev:getRxQueue(rxQueue)
	local txQueue = dev:getTxQueue(txQueue)
	
	local rxMem = memory.createMemPool()	
	local rxBufs = rxMem:bufArray(1)
	
	local txMem = memory.createMemPool(function(buf)
		local pkt = buf:getArpPacket():fill{ 
			ethSrc			= devMac,  
			-- ethDst 		= request.ethSrc

			arpOperation	= arp.OP_REPLY,
			arpHardwareSrc	= devMac,
			-- arpHWDst 	= request.arpHardwareSrc,
			arpProtoSrc 	= devIP,
			-- arpProtoDst 	= request.arpProtoSrc,
			
			pktLength = packetLen }
		end)
	local txBufs = txMem:bufArray(1)
	
	while dpdk.running() do
		rx = rxQueue:tryRecv(rxBufs, 10000)
		if rx > 0 then
			for i, rxBuf in ipairs(rxBufs) do
				local rxPkt = rxBuf:getArpPacket()

				printf("ArpResponderSlave received packet. Checking for ARP request.")
				if rxPkt.eth:getType() == eth.TYPE_ARP and rxPkt.arp:getOperation() == arp.OP_REQUEST then
					printf("ArpResponderSlave received an ARP request. Checking IP.")
					
					if rxPkt.arp:getProtoDstString() == devIP then
						printf("ArpResponderSlave received ARP request with matching IP address. Generating response.")
						
						txBufs:fill(packetLen)
						for i, buf in ipairs(txBufs) do
							local pkt = buf:getArpPacket()

							pkt.eth:setDst(rxPkt.eth:getSrc())

							pkt.arp:setHardwareDst(rxPkt.arp:getHardwareSrc())
							pkt.arp:setProtoDst(rxPkt.arp:getProtoSrc())

							printf("ArpResponderSlave received request:")
							rxBuf:dump()
							printf("ArpResponderSlave replied:")
							buf:dump()
						end
						txQueue:send(txBufs)
					end
				end
			end
		end
	end
end
