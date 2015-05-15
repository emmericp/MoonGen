local dpdk	= require "dpdk"
local ipsec	= require "ipsec"
local memory	= require "memory"
local device	= require "device"

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
	local count = 0
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = srcQueue,
			ethDst = dstQueue,
			ipSrc = "10.0.0.1",
			ipDst = "192.168.1.1",
			udpSrc = 1234,
			udpDst = 5678,	
		}
	end)
	bufs = mem:bufArray(128)

	ipsec.tx_set_key(port, 0, "77777777deadbeef77777777DEADBEEF", "ff0000ff")
	local key, salt = ipsec.tx_get_key(port, 0)
	print("Key:  0x"..key)
	print("Salt: 0x"..salt)

	ipsec.enable(port)
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.payload.uint32[0] = 0xdeadbeef
			pkt.payload.uint32[1] = count
			pkt.payload.uint32[2] = 0xdeadbeef
			count = (count+1) % 0xffffffff
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		-- bufs:offloadUdpChecksums()
		bufs:offloadIPChecksums()
		srcQueue:send(bufs)
	end
	ipsec.disable(port)
end

-- rxSlave logs received packages
function rxSlave(port, queue)
	ipsec.rx_set_key(port, 0, "ffffffffdeadbeef77777777DEADBEEF", "ff0420ff")
	local key, salt = ipsec.rx_get_key(port, 0)
	print("Key:  0x"..key)
	print("Salt: 0x"..salt)

	ipsec.rx_set_ip(port, 0, "1.2.3.4")
	local ip  = ipsec.rx_get_ip(port, 0)
	print("IP: "..ip)
	ipsec.rx_set_ip(port, 1, "0123:4567:89AB:CDEF:1011:1213:1415:1617")
	local ip = ipsec.rx_get_ip(port, 1, false)
	print("IP: "..ip)

	local dev = device.get(port)
	local bufs = memory.bufArray()
	local total = 0
	while dpdk.running() do
		local rx = queue:recv(bufs)
		--for i = 1, rx do
		--	local buf  = bufs[i]
		--	local pkt = buf:getUdpPacket()
		--	printf("C: %u", pkt.payload.uint32[1])
		--end
		-- Dump only one packet per second
		local buf = bufs[rx]
		local pkt = buf:getUdpPacket()
		buf:dump() -- hexdump of received packet (incl. header)
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

