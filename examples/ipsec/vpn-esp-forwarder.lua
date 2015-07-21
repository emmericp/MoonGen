local dpdk	= require "dpdk"
local dpdkc	= require "dpdkc"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"
local ffi	= require "ffi"
local stats	= require "stats"
local math	= require "math"
local ip	= require "proto.ip4"

function master(A, B, size)
	if not A or not B then
		return print("Usage: load/dump_port vpn_port")
	end

	local dev_A = device.config({port=A, rxQueues=1, txQueues=1})
	local dev_B = device.config({port=B, rxQueues=1, txQueues=1})
	device.waitForLinks()

	-- Enable hw crypto engine
	ipsec.enable(A)
	ipsec.enable(B)

	-- Direction: B -> A
	-- Install TX Security Association (SA)
	ipsec.tx_set_key(B, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff")
	-- Install RX Security Association (SA)
	ipsec.rx_set_key(A, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff", 4, "esp", 1)
	ipsec.rx_set_spi(A, 0, 0xdeadbeef, 127)
	ipsec.rx_set_ip(A, 127, "192.168.1.2")

	dpdk.launchLua("vpnEndpoint", dev_B:getRxQueue(0), dev_B:getTxQueue(0),
		"A0:36:9F:3B:71:DA", "192.168.1.1", "A0:36:9F:3B:71:D8", "192.168.1.2", 0xdeadbeef, 0)

	dpdk.launchLua("dumpSlave", dev_A:getRxQueue(0))
	dpdk.launchLua("loadSlave", dev_A:getTxQueue(0), size) --TODO: check different sizes

	dpdk.waitForSlaves()

	-- Disable hw crypto engine
	ipsec.disable(A)
	ipsec.disable(B)
end

function vpnEndpoint(rxQ, txQ, src_mac, src_ip, dst_mac, dst_ip, spi, sa_idx)
	--local p = require("jit.p")
	--require("jit.v").on()
	local bufs = memory.bufArray()
	local new_mem = memory.createMemPool(function(buf)
		buf:getEspPacket():fill{
			--pktLength = new_len,
			ethSrc = src_mac,
			ethDst = dst_mac,
			ip4Protocol = 0x32, --ESP
			ip4Src = src_ip,
			ip4Dst = dst_ip,
			espSPI = spi,
			espSQN = 0,
		}
	end)
	local default_esp_buf = new_mem:alloc(14+20+16) --eth, ip4, esp
	--local ctrRx = stats:newDevRxCounter(rxQ.dev, "plain")
	--local ctrTx = stats:newDevTxCounter(txQ.dev, "plain")
	--p.start("l")
	while dpdk.running() do
		local rx = rxQ:tryRecv(bufs, 0)
		--local esp_bufs = new_mem:bufArray(rx) -- used for encapsulate_slow()
		--encapsulate all received packets
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getIPPacket()
			local len = pkt.ip4:getLength()
			if pkt.ip4:getProtocol() == ip.PROTO_ESP then
				--local secp, secerr = buf:getSecFlags()
				--if secp == 1 and secerr == 0x0 then
				--	local decapsulated_bufs = vpn_decapsulate(
				--		buf, rxQ, "a0:36:9f:3b:71:da")

				--	--TODO: Send to destination network (from VPN tunnel)
				--	--txQ:send(decapsulated_bufs)
				--	decapsulated_bufs:freeAll() --discard all generated pkts (so it wont segfault)
				--else
				--	print("VPN/ESP error: SECP("..secp.."), SECERR("..secerr..")")
				--end
			else
				--modifies the rxBuffers (bufs)
				ipsec.esp_vpn_encapsulate(buf, len, default_esp_buf)
				--esp_bufs[i] = ipsec.esp_vpn_encapsulate_slow(buf, len, new_mem)
				--buf:dump()
			end
		end
		bufs:offloadIPChecksums()
		bufs:offloadIPSec(sa_idx, "esp", 1)
		--esp_bufs:offloadIPChecksums() --used for encapsulate_slow()
		--esp_bufs:offloadIPSec(sa_idx, "esp", 1) --used for encapsulate_slow()
		--Send to VPN tunnel (from destination network)
		txQ:send(bufs)
		--txQ:send(esp_bufs) --used for encapsulate_slow()
		--bufs:freeAll() --used for encapsulate_slow()
		--ctrRx:update()
		--ctrTx:update()
	end
	--p.stop()
	--ctrRx:finalize()
	--ctrTx:finalize()
end

function dumpSlave(rxQ)
	local bufs = memory.bufArray()
	local ctr = stats:newDevRxCounter(rxQ.dev, "plain")
	--TODO: define next hop's MAC address
	local next_hop = "01:02:03:04:05:06"
	local new_mem = memory.createMemPool(function(buf)
		buf:getEthPacket():fill{
			--pktLength = new_len,
			ethSrc = rxQ,
			ethDst = next_hop,
		}
	end)
	local default_eth_buf = new_mem:alloc(14) --eth
	while dpdk.running() do
		local rx = rxQ:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getIPPacket()
			local len = pkt.ip4:getLength()
			local secp, secerr = buf:getSecFlags()
			if pkt.ip4:getProtocol() == ip.PROTO_ESP and secp == 1 and secerr == 0x0 then
				--print("VPN/ESP success: SECP("..secp.."), SECERR("..secerr..")")
				--buf:dump(0)
				--modifies the rxBuffers (bufs)
				ipsec.esp_vpn_decapsulate(buf, len, default_eth_buf)
				--buf:dump(0)
			else
				print("VPN/ESP error: SECP("..secp.."), SECERR("..secerr..")")
				buf:dump()

				local eth_pkt = buf:getEthPacket()
				--'efbeadde' is static: only for testing SPI=0xdeadbeef
				if uhex32(eth_pkt.payload.uint32[5]) ~= "efbeadde" then
					error("SPI wrong, cache error")
				end
			end
		end
		--TODO: Send to destination network (from VPN tunnel)
		--txQ:send(bufs)
		bufs:freeAll()
		ctr:update()
	end
	ctr:finalize()
end

function loadSlave(txQ, size)
	local pkt_size = size or 60
	local numFlows = 256
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = pkt_size,
			ethSrc = txQ,
			ethDst = "10:11:12:13:14:15",
			ip4Dst = "10.0.1.1",
			udpSrc = 1234,
			udpDst = 5678,
		}
	end)
	bufs = mem:bufArray()
	local baseIP = parseIPAddress("10.0.0.1")
	local flow = 0
	--local ctr = stats:newDevTxCounter(txQ.dev, "plain")
	while dpdk.running() do
		bufs:alloc(pkt_size)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip4.src:set(baseIP + flow)
			--flow = incAndWrap(flow, numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		txQ:send(bufs)
		--ctr:update()
	end
	--ctr:finalize()
end
