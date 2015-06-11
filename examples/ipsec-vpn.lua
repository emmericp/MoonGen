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
	-- Enable hw crypto engine
	ipsec.enable(port)

	-- Install TX Security Association (SA), here only Key and Salt.
	-- SPI, Mode and Type are set in the packet
	ipsec.tx_set_key(port, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff")

	--local key, salt = ipsec.tx_get_key(port, 0)
	--print("Key:  0x"..key)
	--print("Salt: 0x"..salt)

	-- Prepare Initialization Vector for the packet
	local iv = ffi.new("union ipsec_iv")
	iv.uint32[0] = 0x01020304
	iv.uint32[1] = 0x05060708

	-- Create a packet Blueprint
	local pkt_len = 86 -- for ESP the packet must be 4 bytes aligned
	local mem = memory.createMemPool(function(buf)
		buf:getEspPacket():fill{
			pktLength = pkt_len,
			ethSrc = srcQueue,
			ethDst = dstQueue,
			ip4Protocol = 0x32, --ESP, 0x33=AH
			ip4Src = "10.0.0.1",
			ip4Dst = "192.168.1.1",
			espSPI = 0xdeadbeef,
			espSQN = 0,
			espIV  = iv,
		}
	end)

	-- Prepare an Array of packets
	bufs = mem:bufArray(10)

	local count = 0
	--while dpdk.running() do
		bufs:alloc(pkt_len)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getEspPacket()
			pkt.esp:setSQN(count) -- increment ESP-SQN with each packet
			pkt.payload.uint32[0] = count -- real payload
			pkt.payload.uint32[1] = 0xffffffff -- real payload
			pkt.payload.uint32[2] = 0xdeadbeef -- real payload
			pkt.payload.uint32[3] = 0xffffffff -- real payload
			ipsec.add_esp_trailer(buf, 16) -- add 20 byte ESP trailer
			buf:offloadIPSec(0, "esp", 1) -- enable hw IPSec in ESP/Encrypted mode, with SA/Key at index 0
			count = count+1
		end
		bufs:offloadIPChecksums()
		srcQueue:send(bufs)
	--end

	-- Disable hw crypto engine
	ipsec.disable(port)
end

-- rxSlave logs received packages
function rxSlave(port, queue)
	-- Enable hw crypto engine
	ipsec.enable(port)

	-- Install RX Security Association (SA)
	ipsec.rx_set_ip(port, 127, "192.168.1.1")
	ipsec.rx_set_spi(port, 0, 0xdeadbeef, 127)
	ipsec.rx_set_key(port, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff", 4, "esp", 1)

	--local key, salt, valid, proto, decrypt, ipv6 = ipsec.rx_get_key(port, 0)
	--print("Key:  0x"..key)
	--print("Salt: 0x"..salt)
	--print("Valid ("..valid.."), Proto ("..proto.."), Decrypt ("..decrypt.."), IPv6 ("..ipv6..")")
	--local ip  = ipsec.rx_get_ip(port, 0)
	--print("IP: "..ip)
	--ipsec.rx_set_ip(port, 1, "0123:4567:89AB:CDEF:1011:1213:1415:1617")
	--local ip = ipsec.rx_get_ip(port, 1, false)
	--print("IP: "..ip)
	--local spi, ip_idx = ipsec.rx_get_spi(port, 0)
	--print("SPI:    0x"..bit.tohex(spi, 8))
	--print("IP_IDX: "..ip_idx)

	local dev = device.get(port)
	local bufs = memory.bufArray()
	local total = 0
	while total < 10 do
		local rx = queue:recv(bufs)
		for i = 1, rx do
			local buf  = bufs[i]
			local pkt = buf:getEspPacket()
			buf:dump(128) -- hexdump of received packet (incl. header)
			printf("counter:   %d", pkt.payload.uint32[0])
			printf("uint32[1]: %x", pkt.payload.uint32[1])
			printf("uint32[2]: %x", pkt.payload.uint32[2])
			printf("uint32[3]: %x", pkt.payload.uint32[3])
		end
		bufs:freeAll()

		local time = dpdk.getTime()
		dpdk.sleepMillis(1000)
		local elapsed = dpdk.getTime() - time
		local pkts = dev:getRxStats(port)
		total = total + pkts
		printf("Received %d packets, current rate %.2f Mpps\n", total, pkts / elapsed / 10^6)
	end
	print("Received "..total.." packets")

	-- Disable hw crypto engine
	ipsec.disable(port)
end

