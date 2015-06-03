local dpdk	= require "dpdk"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"
local ffi	= require "ffi"

function master(txPort, rxPort)
	if not txPort or not rxPort then
		return print("Usage: txPort rxPort")
	end
	local txDev = device.config(txPort, 1)
	local rxDev = device.config(rxPort, 1)
	device.waitForLinks()

	dpdk.launchLua("rxSlave", rxPort, rxDev:getRxQueue(0))
	dpdk.launchLua("txSlave", txPort, txDev:getTxQueue(0), rxDev:getRxQueue(0))

	dpdk.waitForSlaves()
	print("THE END...")
end

-- txSlave sends out (ipsec crypto) packages
function txSlave(port, srcQueue, dstQueue)
	ipsec.enable(port)

	local count = 0
	local iv = ffi.new("union ipsec_iv")
	iv.uint32[0] = 0x01020304
	iv.uint32[1] = 0x05060708
	local mem = memory.createMemPool(function(buf)
		buf:getEspPacket():fill{
			pktLength = 74,
			ethSrc = srcQueue,
			ethDst = dstQueue,
			ip4Protocol = 0x32, --ESP, 0x33=AH
			ip4Src = "10.0.0.1",
			ip4Dst = "192.168.1.1",
			espSPI = 0x01020304,
			espSQN = 0xbbbbbbbb,
			espIV  = iv,
		}
	end)
	bufs = mem:bufArray(128) --Array of 128 pkts

	--SA_IDX 42 is hard coded in TX context descriptor
	ipsec.tx_set_key(port, 42, "77777777deadbeef77777777DEADBEEF", "ff0000ff")
	local key, salt = ipsec.tx_get_key(port, 42)
	print("Key:  0x"..key)
	print("Salt: 0x"..salt)

	while dpdk.running() do
		bufs:alloc(74)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getEspPacket()
			pkt.payload.uint8[0] = 0xee -- real payload
			--pkt.payload.uint32[0] = 0xeeeeeeee -- real payload
			ipsec.add_esp_trailer(buf, 1) -- add 20 byte ESP trailer
			count = (count+1) % 0xffffffff
		end
		bufs:offloadIPChecksums()
		bufs:offloadIPSec(42, "esp", 1)
		srcQueue:send(bufs)
	end
	ipsec.disable(port)
end

-- rxSlave logs received packages
function rxSlave(port, queue)
	ipsec.rx_set_key(port, 0, "ffffffffdeadbeef77777777DEADBEEF", "ff0420ff")
	local key, salt, valid, proto, decrypt, ipv6 = ipsec.rx_get_key(port, 0)
	print("Key:  0x"..key)
	print("Salt: 0x"..salt)
	print("Valid ("..valid.."), Proto ("..proto.."), Decrypt ("..decrypt.."), IPv6 ("..ipv6..")")

	ipsec.rx_set_ip(port, 0, "1.2.3.4")
	local ip  = ipsec.rx_get_ip(port, 0)
	print("IP: "..ip)
	ipsec.rx_set_ip(port, 1, "0123:4567:89AB:CDEF:1011:1213:1415:1617")
	local ip = ipsec.rx_get_ip(port, 1, false)
	print("IP: "..ip)

	ipsec.rx_set_spi(port, 0, 0xdeadbeef, 0)
	local spi, ip_idx = ipsec.rx_get_spi(port, 0)
	print("SPI:    0x"..bit.tohex(spi, 8))
	print("IP_IDX: "..ip_idx)

	local dev = device.get(port)
	local bufs = memory.bufArray()
	local total = 0
	while dpdk.running() do
		local rx = queue:recv(bufs)
		--for i = 1, rx do
		--	local buf  = bufs[i]
		--	local pkt = buf:getEspPacket()
		--	printf("C: %u", pkt.payload.uint32[1])
		--end
		-- Dump only one packet per second
		local buf = bufs[rx]
		local pkt = buf:getEspPacket()
		buf:dump(128) -- hexdump of received packet (incl. header)
		printf("H: 0x%x", pkt.payload.uint32[0])
		printf("C: 0x%x (%u)", pkt.payload.uint32[1], pkt.payload.uint32[1])
		printf("T: 0x%x", pkt.payload.uint32[2])
		bufs:freeAll()

		local time = dpdk.getTime()
		dpdk.sleepMillis(1000)
		local elapsed = dpdk.getTime() - time
		local pkts = dev:getRxStats(port)
		total = total + pkts
		printf("Received %d packets, current rate %.2f Mpps\n", total, pkts / elapsed / 10^6)
	end
	print("Received "..total.." packets")
end

