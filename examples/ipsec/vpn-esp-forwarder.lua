local dpdk	= require "dpdk"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"
local ffi	= require "ffi"
local stats	= require "stats"

function master(txPort, rxPort)
	if not txPort or not rxPort then
		return print("Usage: txPort rxPort")
	end
	local txDev = device.config(txPort, 1)
	local rxDev = device.config(rxPort, 1)
	device.waitForLinks()

	dpdk.launchLua("dumpSlave", rxPort, rxDev:getRxQueue(0), rxDev)
	--dpdk.launchLua("encryptSlave", txPort, rxPort, txDev:getTxQueue(0), rxDev:getRxQueue(0))
	-- TODO: add decryptSlave, for the other VPN-End-Point
	dpdk.launchLua("loadSlave", txPort, txDev:getTxQueue(0), txDev, 256)

	dpdk.waitForSlaves()
end

function loadSlave(port, queue, dev, numFlows)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = queue,
			ethDst = "10:11:12:13:14:15",
			ip4Dst = "192.168.1.1",
			udpSrc = 1234,
			udpDst = 5678,
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("10.0.0.1")
	local flow = 0
	local ctr = stats:newDevTxCounter(dev, "plain")
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip4.src:set(baseIP + flow)
			flow = incAndWrap(flow, numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		queue:send(bufs)
		ctr:update()
	end
	ctr:finalize()
end

function dumpSlave(port, queue, dev)
	local rxCtr = stats:newDevRxCounter(dev, "plain")
	local iv = ffi.new("union ipsec_iv")
	iv.uint32[0] = 0x01020304
	iv.uint32[1] = 0x05060708
	local new_mem = memory.createMemPool(function(buf)
		buf:getEspPacket():fill{
			--pktLength = new_len,
			ethSrc = queue,
			ethDst = "a0:36:9f:3b:71:da", --dstQueue,
			ip4Protocol = 0x32, --ESP
			ip4Src = "192.168.1.1",
			ip4Dst = "192.168.1.2",
			espSPI = 0xdeadbeef,
			espSQN = 0,
			espIV  = iv,
		}
	end)
	local new_bufs = new_mem:bufArray(1) -- allocate one ESP packet

	local bufs = memory.bufArray()
	while dpdk.running() do
		local rx = queue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			print("Original Pkt:")
			buf:dump(128)
			local pkt = buf:getIPPacket()
			local eth_pkt = buf:getEthPacket()
			local len = pkt.ip4:getLength()

			local new_len = 14+20+16+len+20 -- eth(14), ip4(20), esp(16), __pkt__(len), esp_trailer(20)
			new_bufs:alloc(new_len)
			for _, new_buf in ipairs(new_bufs) do --FIXME: there is actually only one buf/pkt in new_bufs
				local new_pkt = new_buf:getEspPacket()
				new_pkt:setLength(new_len)
				-- copy old pkt (starting with IP header) into new ESP pkt
				for i = 0, len-1 do
					new_pkt.payload.uint8[i] = eth_pkt.payload.uint8[i]
				end
				print("New Pkt:")
				new_buf:dump(128)
				ipsec.add_esp_trailer(new_buf, len, 0x4) -- Tunnel mode: next_header = 0x4 (IPv4)
				print("New Pkt (with ESP Trailer):")
				new_buf:dump(128)
			end
			--TODO:
			--new_bufs:offloadIPChecksums()
			--new_bufs:offloadIPSec(0, "esp", 1)
			--queue:send(new_bufs)
		end
		bufs:freeAll()
		rxCtr:update()
	end
	rxCtr:finalize()
end

-- encryptSlave encapsulates and encrypts and forwards incoming packets with IPSec/ESP (AES128-GCM)
function encryptSlave(txPort, rxPort, txQueue, rxQueue)
	-- Enable hw crypto engine
	ipsec.enable(txPort)

	-- Install TX Security Association (SA), here only Key and Salt.
	-- SPI, Mode and Type are set in the packet
	ipsec.tx_set_key(txPort, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff")

	-- Prepare Initialization Vector for the packet
	-- FIXME: This should be random and unique
	local iv = ffi.new("union ipsec_iv")
	iv.uint32[0] = 0x01020304
	iv.uint32[1] = 0x05060708

	-- Create a packet Blueprint
	local pkt_len = 86 -- for ESP the packet must be 4 bytes aligned
	local mem = memory.createMemPool(function(buf)
		buf:getEspPacket():fill{
			pktLength = pkt_len,
			ethSrc = srcQueue,
			ethDst = "a0:36:9f:3b:71:da", --dstQueue,
			ip4Protocol = 0x32, --ESP
			ip4Src = "192.168.1.1",
			ip4Dst = "192.168.1.2",
			espSPI = 0xdeadbeef,
			espSQN = 0, -- FIXME: This should be dynamic
			espIV  = iv,
		}
	end)

	local bufs = memory.bufArray()
	while dpdk.running() do
		local rx = rxQueue:recv(bufs)
		local new_bufs = mem:bufArray(rx) -- allocate space for the new, encapsulated packets
		new_bufs:alloc(pkt_len) -- FIXME: does this mean we have fixed pkt lengths only?
		for i = 1, rx do
			local buf  = bufs[i] -- original packet buffer
			local new_buf = new_bufs[i] -- new packet buffer for encapsulated packet
			local ip_pkt = buf:getIPPacket() -- original IP packet
			local esp_pkt = new_buf:getEspPacket() -- new ESP packet

			buf:dump(128) -- TODO: DEBUG
			local ip_header = ip_pkt:getHeader()
			local len = ip_header:getLengt()
			-- TODO: put original packet into ESP packet

			-- add 20 byte trailer, next_hdr = IPv4(0x04)/IPv6(0x29)
			-- TODO: adopt length to the original packet's length
			ipsec.add_esp_trailer(buf, 16, 0x04)
		end
		bufs:freeAll() -- free original packet buffer
		new_bufs:offloadIPChecksums()
		new_bufs:offloadIPSec(0, "esp", 1) -- enable hw IPSec in ESP/Encrypted mode, with SA/Key at index 0
		txQueue:send(new_bufs)
	end

	-- Disable hw crypto engine
	ipsec.disable(txPort)
end

