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

	dpdk.launchLua("rxSlave", rxPort, rxDev:getRxQueue(0), rxDev)
	dpdk.launchLua("txSlave", txPort, txDev:getTxQueue(0), rxDev:getRxQueue(0), txDev)

	dpdk.waitForSlaves()
	print("THE END...")
end

-- txSlave sends out (ipsec crypto) packages
function txSlave(port, srcQueue, dstQueue, txDev)
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
	local pkt_len = 70 -- 70 bytes is the minimum for IPv4/AHv4
	local mem = memory.createMemPool(function(buf)
		buf:getAhPacket():fill{
			pktLength = pkt_len,
			ethSrc = srcQueue,
			ethDst = "a0:36:9f:3b:71:da", --dstQueue,
			ip4Protocol = 0x33, --AH, 0x32=ESP
			ip4Src = "192.168.1.1",
			ip4Dst = "192.168.1.2",
			ahSPI = 0xdeadbeef,
			ahSQN = 0,
			ahIV  = iv,
			ahNextHeader = 0x11, --UDP
		}
	end)

	local txCtr = stats:newDevTxCounter(txDev, "plain")

	-- Prepare an Array of packets
	--bufs = mem:bufArray(10)
	bufs = mem:bufArray(128)

	local count = 0
	while dpdk.running() do
		bufs:alloc(pkt_len)
		for _, buf in ipairs(bufs) do
			--local pkt = buf:getAhPacket()
			--pkt.ah:setSQN(count) -- increment AH-SQN with each packet
			--pkt.payload.uint16[0] = bswap16(12) -- UDP src port (not assigned to service)
			--pkt.payload.uint16[1] = bswap16(14) -- UDP dst port (not assigned to service)
			--pkt.payload.uint16[2] = bswap16(16) -- UDP len (header + payload in bytes)
			--pkt.payload.uint16[3] = bswap16(0)  -- UDP checksum (0 = unused)
			--pkt.payload.uint32[2] = 0xdeadbeef -- real payload
			--pkt.payload.uint32[3] = 0xffffffff -- real payload
			buf:offloadIPSec(0, "ah") -- enable hw IPSec in AH mode, with SA/Key at index 0
			--count = count+1
		end
		bufs:offloadIPChecksums()
		--bufs:offloadIPSec(0, "ah")
		srcQueue:send(bufs)

		-- Update TX counter
		txCtr:update()
	end

	-- Finalize TX counter
	txCtr:finalize()

	-- Disable hw crypto engine
	ipsec.disable(port)
end

-- rxSlave logs received packages
function rxSlave(port, queue, rxDev)
	-- Enable hw crypto engine
	ipsec.enable(port)

	-- Install RX Security Association (SA)
	ipsec.rx_set_ip(port, 127, "192.168.1.2")
	ipsec.rx_set_spi(port, 0, 0xdeadbeef, 127)
	ipsec.rx_set_key(port, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff", 4, "ah")

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

	local rxCtr = stats:newDevRxCounter(rxDev, "plain")

	local bufs = memory.bufArray()
	while dpdk.running() do
		local rx = queue:recv(bufs)
		for i = rx, rx do
			local buf  = bufs[i]
			--local pkt = buf:getAhPacket()
			--local secp, secerr = buf:getSecFlags()
			--print("IPSec HW status: SECP (" .. secp .. ") SECERR (0x" .. bit.tohex(secerr, 1) .. ")")
			--buf:dump(128) -- hexdump of received packet (incl. header)
			--printf("uint32[0]: %x", pkt.payload.uint32[0]) --UDP header
			--printf("uint32[1]: %x", pkt.payload.uint32[1]) --UDP header
			--printf("uint32[2]: %x", pkt.payload.uint32[2])
			--printf("uint32[3]: %x", pkt.payload.uint32[3])
		end
		bufs:freeAll()

		-- Update RX counter
		rxCtr:update()
	end
	-- Finalize RX counter
	rxCtr:finalize()

	-- Disable hw crypto engine
	ipsec.disable(port)
end

