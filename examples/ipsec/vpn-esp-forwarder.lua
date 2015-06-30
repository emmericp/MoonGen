local dpdk	= require "dpdk"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"
local ffi	= require "ffi"
local stats	= require "stats"
local math	= require "math"
local ip	= require "proto.ip4"

function master(A, B)
	if not A or not B then
		return print("Usage: A B")
	end

	local dev_A = device.config({port=A, rxQueues=1, txQueues=1+1})
	local dev_B = device.config({port=B, rxQueues=1, txQueues=1})
	device.waitForLinks()

	dpdk.launchLua("vpnEndpoint", B, dev_B:getRxQueue(0), dev_B:getTxQueue(0), dev_B)
	dpdk.launchLua("vpnEndpoint", A, dev_A:getRxQueue(0), dev_A:getTxQueue(0), dev_A)

	dpdk.launchLua("loadSlave", A, dev_A:getTxQueue(1), dev_A, 256)

	dpdk.waitForSlaves()
end

function vpn_decapsulate(buf, src_mac, dst_mac)
	local new_mem = memory.createMemPool(function(buf)
		buf:getEthPacket():fill{
			--pktLength = new_len,
			ethSrc = src_mac,
			ethDst = dst_mac,
		}
	end)
	local new_bufs = new_mem:bufArray(1) -- allocate one ETH packet

	print("Original (ESP) Pkt:")
	local secp, secerr = buf:getSecFlags()
	print("ESP HW status: SECP (" .. secp .. ") SECERR (0x" .. bit.tohex(secerr, 1) .. ")")
	buf:dump()
	local pkt = buf:getIPPacket()
	local esp_pkt = buf:getEspPacket()

	local len = pkt.ip4:getLength()
	local extra_pad = pkt.payload.uint8[len-20-16-1-1] --IP4(20), ICV(16), next_hdr(1), array_starts_at_0(1), less 2 bytes standard padding
	-- eth(14), pkt(len), pad(extra_pad), outer_ip(20), esp_header(16), esp_trailer(20)
	local new_len = 14+len-extra_pad-20-16-20
	print("Len, New_len, extra_pad: " .. len .." ".. new_len .." "..extra_pad)

	new_bufs:alloc(new_len)
	local new_buf = new_bufs[1]
	local new_pkt = new_buf:getEthPacket()
	new_pkt:setLength(new_len)

	-- copy old (inner) pkt into new ETH pkt
	for i = 0, new_len-14-1 do
		new_pkt.payload.uint8[i] = esp_pkt.payload.uint8[i]
	end

	print("New Pkt:")
	new_buf:dump()

	return new_bufs
end

function vpn_encapsulate(buf, spi, sa_idx, src_mac, src_ip, dst_mac, dst_ip)
	local iv = ffi.new("union ipsec_iv")
	iv.uint32[0] = math.random(0, 2^32-1)
	iv.uint32[1] = math.random(0, 2^32-1)
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
			espIV  = iv,
		}
	end)
	local new_bufs = new_mem:bufArray(1) -- allocate one ESP packet

	local pkt = buf:getIPPacket()
	local eth_pkt = buf:getEthPacket()

	local len = pkt.ip4:getLength()
	local extra_pad = ipsec.calc_extra_pad(len) --for 4 byte alignment
	-- eth(14), ip4(20), esp(16), pkt(len), pad(extra_pad), esp_trailer(20)
	local new_len = 14+20+16+len+extra_pad+20

	new_bufs:alloc(new_len)
	local new_buf = new_bufs[1]
	local new_pkt = new_buf:getEspPacket()
	new_pkt:setLength(new_len)

	-- copy old pkt (starting with IP header) into new ESP pkt
	for i = 0, len-1 do
		new_pkt.payload.uint8[i] = eth_pkt.payload.uint8[i]
	end

	ipsec.add_esp_trailer(new_buf, len, 0x4) -- Tunnel mode: next_header = 0x4 (IPv4)

	new_bufs:offloadIPChecksums()
	new_bufs:offloadIPSec(sa_idx, "esp", 1)

	return new_bufs
end

function loadSlave(port, queue, dev, numFlows)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = queue,
			ethDst = "10:11:12:13:14:15",
			ip4Dst = "10.0.1.1",
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

function vpnEndpoint(port, rxQ, txQ, dev)
	local rxCtr = stats:newDevRxCounter(dev, "plain")

	local bufs = memory.bufArray()
	while dpdk.running() do
		local rx = rxQ:recv(bufs)
		--encapsulate all received packets
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getIPPacket()

			if pkt.ip4:getProtocol() == ip.PROTO_ESP then
				local decapsulated_bufs = vpn_decapsulate(
					buf, rxQ, "a0:36:9f:3b:71:da")

				--TODO: Send to destination network (from VPN tunnel)
				--txQ:send(decapsulated_bufs)
				decapsulated_bufs:freeAll() --discard all generated pkts (so it wont segfault)
			else
				--print("Original SRC pkt")
				--buf:dump()
				local encapsulated_bufs = vpn_encapsulate(
					buf, 0xdeadbeef, 0,
					rxQ, "192.168.1.1", "a0:36:9f:3b:71:da", "192.168.1.2")

				--TODO: Send to VPN tunnel (from destination network)
				txQ:send(encapsulated_bufs)
				--encapsulated_bufs:freeAll() --discard all generated pkts (so it wont segfault)
			end
		end
		bufs:freeAll()
		rxCtr:update()
	end
	rxCtr:finalize()
end
