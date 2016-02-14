local dpdk	= require "dpdk"
local dpdkc	= require "dpdkc"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"
local ffi	= require "ffi"
local stats	= require "stats"
local math	= require "math"
local ip	= require "proto.ip4"

-- narva
--./build/MoonGen examples/ipsec/vpn-esp-forwarder.lua 0 1
function narva(A, B, size)
	if not A or not B then
		return print("Usage: plain-in crypt-out")
	end

	local dev_A = device.config({port=A, rxQueues=1, txQueues=1})
	local dev_B = device.config({port=B, rxQueues=1, txQueues=1})
	device.waitForLinks()

	-- Enable hw crypto engine
	ipsec.enable(B)
	ipsec.tx_set_key(B, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff")
	dpdk.launchLua("vpnEndpoint", dev_A:getRxQueue(0), dev_B:getTxQueue(0),
	        "90:E2:BA:1F:8D:44", "1.1.1.1", "90:E2:BA:35:B5:80", "2.2.2.2", 0xdeadbeef, 0)
	dpdk.waitForSlaves()
	-- Disable hw crypto engine
	ipsec.disable(B)
end

--klaipeda
--for s in $(seq 60 64 1458) 1458; do timeout -s INT 13 ./build/MoonGen examples/ipsec/vpn-esp-forwarder.lua 1 0 $s; echo "Size:" $s; echo "======"; echo ""; done;
function klaipeda(A, B, size)
	if not A or not B then
		return print("Usage: load dump pkt-size")
	end

	local dev_A = device.config({port=A, rxQueues=1, txQueues=1})
	local dev_B = device.config({port=B, rxQueues=1, txQueues=1})
	device.waitForLinks()

	-- Enable hw crypto engine
	ipsec.enable(B)

	ipsec.rx_set_key(B, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff", 4, "esp", 1)
	ipsec.rx_set_spi(B, 0, 0xdeadbeef, 127)
	ipsec.rx_set_ip(B, 127, "2.2.2.2")

	dpdk.launchLua("dumpSlave", dev_B:getRxQueue(0))
	dpdk.launchLua("loadSlave", dev_A:getTxQueue(0), size, "90:E2:BA:2C:CB:02")
	dpdk.waitForSlaves()

	-- Disable hw crypto engine
	ipsec.disable(B)
end

--omanyte
function omanyte(A, B, size)
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

function master(host, A, B, size)
	if host == "omanyte" then
		omanyte(A,B,size)
	elseif host == "klaipeda" then
		klaipeda(A,B,size)
	elseif host == "narva" then
		narva(A,B,size)
	else
		return print("Usage: omanyte|klaipeda|narva A B size")
	end
end

function vpnEndpoint(rxQ, txQ, src_mac, src_ip, dst_mac, dst_ip, spi, sa_idx)
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
	while dpdk.running() do
		local rx = rxQ:tryRecv(bufs, 0)
		local esp_bufs = new_mem:bufArray(rx) -- used for encapsulate()
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
				esp_bufs[i] = ipsec.esp_vpn_encapsulate(buf, len, new_mem)
				--buf:dump()
			end
		end
		esp_bufs:offloadIPChecksums() --used for encapsulate()
		esp_bufs:offloadIPSec(sa_idx, "esp", 1) --used for encapsulate()
		--Send to VPN tunnel (from destination network)
		txQ:send(esp_bufs) --used for encapsulate()
		bufs:freeAll() --used for encapsulate()
	end
end

function dumpSlave(rxQ, next_hop)
	local bufs = memory.bufArray()
	local ctr = stats:newDevRxCounter(rxQ.dev, "plain")
	--define next hop's MAC address
	local next_hop = next_hop or "01:02:03:04:05:06"
	local new_mem = memory.createMemPool(function(buf)
		buf:getEthPacket():fill{
			--pktLength = new_len,
			ethSrc = rxQ,
			ethDst = next_hop,
		}
	end)
	while dpdk.running() do
		local rx = rxQ:tryRecv(bufs, 0)
		local eth_bufs = new_mem:bufArray(rx)
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getIPPacket()
			local len = pkt.ip4:getLength()
			local secp, secerr = buf:getSecFlags()
			if pkt.ip4:getProtocol() == ip.PROTO_ESP and secp == 1 and secerr == 0x0 then
				--print("VPN/ESP success: SECP("..secp.."), SECERR("..secerr..")")
				--buf:dump()
				eth_bufs[i] = ipsec.esp_vpn_decapsulate(buf, len, new_mem)
				--eth_bufs[i]:dump()
			elseif pkt.ip4:getProtocol() == ip.PROTO_ESP then
				print("VPN/ESP error: SECP("..secp.."), SECERR("..secerr..")")
				buf:dump()
			else
				buf:dump(0)
			end
		end
		--TODO: Send to destination network (from VPN tunnel)
		--eth_bufs:offloadIPChecksums()
		--txQ:send(eth_bufs)
		eth_bufs:freeAll()
		bufs:freeAll()
		ctr:update()
	end
	ctr:finalize()
end

function loadSlave(txQ, size, next_hop)
	local next_hop = next_hop or "11:22:33:44:55:66"
	local pkt_size = size or 60
	local numFlows = 256
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = pkt_size,
			ethSrc = txQ,
			ethDst = next_hop,
			ip4Src = "10.0.1.1",
			ip4Dst = "10.0.2.1",
			udpSrc = 1234,
			udpDst = 5678,
		}
	end)
	bufs = mem:bufArray()
	--local ctr = stats:newDevTxCounter(txQ.dev, "plain")
	while dpdk.running() do
		bufs:alloc(pkt_size)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		txQ:send(bufs)
		--ctr:update()
	end
	--ctr:finalize()
end
