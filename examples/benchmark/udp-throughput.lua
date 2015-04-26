local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"

local ffi	= require "ffi"

function master(...)
	local txPort, numFlows, rate = tonumberall(...)
	if not txPort or not numFlows then
		print("usage: txPort numFlows [rate]")
		return
	end
	rate = rate or 10000
	local rxMempool = memory.createMemPool()
	local txDev = device.config(txPort, rxMempool, 2, 2)
	txDev:wait()
	txDev:getTxQueue(0):setRate(rate)
	dpdk.launchLua("loadSlave", txPort, 0, numFlows)
	dpdk.waitForSlaves()
end

function loadSlave(port, queue, numFlows)
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		local pkt = buf:getUDPPacket()
		local data = ffi.cast("uint8_t*", buf.pkt.data)
		-- src/dst mac
		for i = 0, 11 do
			data[i] = i
		end
		-- TODO: implement structs and some utility functions for reasonable defaults
		data[12] = 0x08 -- ethertype (IPv4)
		data[13] = 0x00
		data[14] = 0x45 -- Version, IHL
		data[15] = 0x00 -- DSCP/ECN
		data[16] = 0x00 -- length (46)
		data[17] = 0x2E
		data[18] = 0x00 --id
		data[19] = 0x00
		data[20] = 0x00 -- flags/fragment offset
		data[21] = 0x00 -- fragment offset
		data[22] = 0x80 -- ttl
		data[23] = 0x11 -- protocol (UDP)
		data[24] = 0x00 -- checksum (offloaded to NIC)
		data[25] = 0x00
		data[26] = 0x01 -- src ip (1.2.3.4)
		data[27] = 0x02
		data[28] = 0x03
		data[29] = 0x04
		data[30] = 0x0A -- dst ip (10.0.0.1)
		data[31] = 0x00
		data[32] = 0x00
		data[33] = 0x01
		data[34] = 0x00 --bit.rshift(port, 8)
		data[35] = 0x01 --bit.band(port, 0xFF) -- src port
		data[36] = 0x00 --bit.rshift(port, 8)
		data[37] = 0x01 --bit.band(port, 0xFF) -- dst port
		data[38] = 0x00
		data[39] = 0x1A -- length (26)
		data[40] = 0x00 -- checksum (offloaded to NIC)
		data[41] = 0x00 -- checksum (offloaded to NIC)
		--printf("%08X", pkt.ip.src.uint32)
	end)
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(128)
	local baseIP = 0x01020304 -- TODO: ip.parse("1.2.3.4")
	local counter = 0
	while dpdk.running() do
		bufs:alloc(60)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUDPPacket()
			pkt.ip.src:set(baseIP + counter)
			counter = incAndWrap(counter, numFlows)
		end
		-- UDP checksums are optional, so using just IPv4 checksums would be sufficient here
		bufs:offloadUdpChecksums()
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("Sent %d packets", totalSent)
end

