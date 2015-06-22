-- FIXME: this file is ugly because it doesn't abstract anything properly
local mod = {}

local ffi		= require "ffi"
local dpdkc		= require "dpdkc"
local dpdk		= require "dpdk"
local device	= require "device"
local eth		= require "proto.ethernet"
local memory	= require "memory"
local timer		= require "timer"

require "proto.ptp"

local dev = device.__devicePrototype
local rxQueue = device.__rxQueuePrototype
local txQueue = device.__txQueuePrototype

-- registers, mostly 82599/X540-specific
local RXMTRL			= 0x00005120
local TSYNCRXCTL		= 0x00005188
local RXSTMPL			= 0x000051E8
local RXSTMPH			= 0x000051A4
local RXSATRH			= 0x000051A8
local ETQF_0			= 0x00005128
local ETQS_0			= 0x0000EC00

local TSYNCTXCTL		= 0x00008C00
local TXSTMPL			= 0x00008C04
local TXSTMPH			= 0x00008C08
local TIMEINCA			= 0x00008C14 -- X540 only
local TIMINCA			= 0x00008C14 -- 82599 only (yes, the datasheets actually uses two different names)

local SYSTIMEL			= 0x00008C0C
local SYSTIMEH			= 0x00008C10
local TIMEADJL			= 0x00008C18
local TIMEADJH			= 0x00008C1C

-- 82580 (and others gbit cards?) registers
local TSAUXC			= 0x0000B640
local TIMINCA_82580		= 0x0000B608
local TSYNCRXCTL_82580	= 0x0000B620
local TSYNCTXCTL_82580	= 0x0000B614
local TXSTMPL_82580		= 0x0000B618
local TXSTMPH_82580		= 0x0000B61C
local RXSTMPL_82580		= 0x0000B624
local RXSTMPH_82580		= 0x0000B628
local RXSATRH_82580		= 0x0000B630
local ETQF_82580_0		= 0x00005CB0

local SYSTIMEL_82580	= 0x0000B600
local SYSTIMEH_82580	= 0x0000B604
local TIMEADJL_82580	= 0x0000B60C
local TIMEADJH_82580	= 0x0000B610


local SRRCTL_82580		= {}
for i = 0, 7 do
	SRRCTL_82580[i] = 0x0000C00C + 0x40 * i
end

-- TODO: support for more registers

-- bit names in registers
local TSYNCRXCTL_RXTT		= 1
local TSYNCRXCTL_TYPE_OFFS	= 1
local TSYNCRXCTL_TYPE_MASK	= bit.lshift(7, TSYNCRXCTL_TYPE_OFFS)
local TSYNCRXCTL_EN		= bit.lshift(1, 4)

local TSYNCTXCTL_TXTT		= 1
local TSYNCTXCTL_EN		= bit.lshift(1, 4)

local ETQF_FILTER_ENABLE		= bit.lshift(1, 31)
local ETQF_FILTER_ENABLE_82580	= bit.lshift(1, 26)
local ETQF_QUEUE_ENABLE_82580	= bit.lshift(1, 31)
local ETQF_IEEE_1588_TIME_STAMP	= bit.lshift(1, 30)

local ETQS_RX_QUEUE_OFFS	= 16
local ETQS_QUEUE_ENABLE		= bit.lshift(1, 31)

local TIMINCA_IP_OFFS		= 24 -- 82599 only

local TSAUXC_DISABLE		= bit.lshift(1, 31)

local SRRCTL_TIMESTAMP		= bit.lshift(1, 30)

-- offloading flags
local PKT_TX_IEEE1588_TMST	= 0x8000
local PKT_TX_IP_CKSUM		= 0x1000
local PKT_TX_UDP_CKSUM		= 0x6000


---
-- @deprecated
function mod.fillL2Packet(buf, seq)
	seq = seq or (((3 * 255) + 2) * 255 + 1) * 255
	buf.pkt.pkt_len = 60
	buf.pkt.data_len = 60
	buf:getPtpPacket():fill{
		ptpSequenceID = seq
	}
	buf.ol_flags = bit.bor(buf.ol_flags, PKT_TX_IEEE1588_TMST)
end

---
-- @deprecated
function mod.readSeq(buf)
	if buf.pkt.pkt_len < 4 then
	  return nil
	end
	return buf:getPtpPacket().ptp:getSequenceID()
end

---
-- @deprecated
function mod.fillPacket(buf, port, size, ignoreBadSize)
	size = size or 80
	-- min 76 bytes as the NIC refuses to timestamp 'truncated' PTP packets
	if size < 76 and not ignoreBadSize then
		error("time stamped UDP packets must be at least 76 bytes long")
	end
	buf.pkt.pkt_len = size
	buf.pkt.data_len = size
	buf.ol_flags = bit.bor(buf.ol_flags, PKT_TX_IEEE1588_TMST)
	local data = ffi.cast("uint8_t*", buf.pkt.data)
	data[0] = 0x00 -- dst mac
	data[1] = 0x25
	data[2] = 0x90
	data[3] = 0xED
	data[4] = 0xBD
	data[5] = 0xDD
	data[6] = 0x00 -- src mac
	data[7] = 0x25
	data[8] = 0x90
	data[9] = 0xED
	data[10] = 0xBD
	data[11] = 0xDD
	data[12] = 0x08 -- ethertype (IPv4)
	data[13] = 0x00
	data[14] = 0x45 -- Version, IHL
	data[15] = 0x00 -- DSCP/ECN
	data[16] = bit.rshift(size - 14, 8) -- length
	data[17] = bit.band(size - 14, 0xFF)
	data[18] = 0x00 --id
	data[19] = 0x00
	data[20] = 0x00 -- flags/fragment offset
	data[21] = 0x00 -- fragment offset
	data[22] = 0x80 -- ttl
	data[23] = 0x11 -- protocol (UDP)
	data[24] = 0x00 
	data[25] = 0x00
	data[26] = 0x01 -- src ip (1.2.3.4)
	data[27] = 0x02
	data[28] = 0x03
	data[29] = 0x04
	data[30] = 0x0A -- dst ip (10.0.0.1)
	data[31] = 0x00
	data[32] = 0x00
	data[33] = 0x01
	data[34] = bit.rshift(port, 8)
	data[35] = bit.band(port, 0xFF) -- src port
	data[36] = bit.rshift(port, 8)
	data[37] = bit.band(port, 0xFF) -- dst port
	data[38] = bit.rshift(size - 34, 8)
	data[39] = bit.band(size - 34, 0xFF)
	data[40] = 0x00 -- checksum (offloaded to NIC)
	data[41] = 0x00 -- checksum (offloaded to NIC)
	data[42] = 0x00 -- message id
	data[43] = 0x02 -- ptp version
end

-- TODO these functions should also use the upper 32 bit...

--- try to read a tx timestamp if one is available, returns -1 if no timestamp is available
function mod.tryReadTxTimestamp(port)
	local isIgb = device.get(port):getPciId() == device.PCI_ID_82580
	if isIgb then
		if bit.band(dpdkc.read_reg32(port, TSYNCTXCTL_82580), TSYNCTXCTL_TXTT) == 0 then
			return nil
		end
		local low = dpdkc.read_reg32(port, TXSTMPL_82580)
		local high = dpdkc.read_reg32(port, TXSTMPH_82580)
		return low
	else
		if bit.band(dpdkc.read_reg32(port, TSYNCTXCTL), TSYNCTXCTL_TXTT) == 0 then
			return nil
		end
		local low = dpdkc.read_reg32(port, TXSTMPL)
		local high = dpdkc.read_reg32(port, TXSTMPH)
		return low
	end
end

function mod.tryReadRxTimestamp(port)
	local isIgb = device.get(port):getPciId() == device.PCI_ID_82580
	if isIgb then
		if bit.band(dpdkc.read_reg32(port, TSYNCRXCTL_82580), TSYNCRXCTL_RXTT) == 0 then
			return nil
		end
		local low = dpdkc.read_reg32(port, RXSTMPL_82580)
		local high = dpdkc.read_reg32(port, RXSTMPH_82580)
		return low
	else
		if bit.band(dpdkc.read_reg32(port, TSYNCRXCTL), TSYNCRXCTL_RXTT) == 0 then
			return nil
		end
		local low = dpdkc.read_reg32(port, RXSTMPL)
		local high = dpdkc.read_reg32(port, RXSTMPH)
		return low
	end
end

local function startTimerIxgbe(port, id)
	-- start system timer, this differs slightly between the two currently supported ixgbe-chips
	if id == device.PCI_ID_X540 then
		dpdkc.write_reg32(port, TIMEINCA, 1)
	elseif id == device.PCI_ID_82599 then
		dpdkc.write_reg32(port, TIMINCA, bit.bor(2, bit.lshift(2, TIMINCA_IP_OFFS)))
	else -- should not happen
		errorf("unsupported ixgbe device %s", device.getDeviceName(port))
	end
end

local function startTimerIgb(port, id)
	if id == device.PCI_ID_82580 then
		-- start the timer
		dpdkc.write_reg32(port, TIMINCA_82580, 1)
		dpdkc.write_reg32(port, TSAUXC, bit.band(dpdkc.read_reg32(port, TSAUXC), bit.bnot(TSAUXC_DISABLE)))

	else
		errorf("unsupported igb device %s", device.getDeviceName(port))
	end
end

local function enableRxTimestampsIxgbe(port, queue, udpPort, id)
	startTimerIxgbe(port, id)
	-- l2 rx filter
	dpdkc.write_reg32(port, ETQF_0, bit.bor(ETQF_FILTER_ENABLE, ETQF_IEEE_1588_TIME_STAMP, eth.TYPE_PTP))
	dpdkc.write_reg32(port, ETQS_0, bit.bor(ETQS_QUEUE_ENABLE, bit.lshift(queue, ETQS_RX_QUEUE_OFFS)))
	-- L3 filter
	-- TODO
	-- enable rx timestamping
	local val = dpdkc.read_reg32(port, TSYNCRXCTL)
	val = bit.bor(val, TSYNCRXCTL_EN)
	val = bit.band(val, bit.bnot(TSYNCRXCTL_TYPE_MASK))
	val = bit.bor(val, bit.lshift(2, TSYNCRXCTL_TYPE_OFFS))
	dpdkc.write_reg32(port, TSYNCRXCTL, val)
	-- timestamp udp messages
	local val = bit.lshift(udpPort, 16)
	dpdkc.write_reg32(port, RXMTRL, val)
end

local function enableTxTimestampsIxgbe(port, queue, udpPort, id)
	startTimerIxgbe(port, id)
	local val = dpdkc.read_reg32(port, TSYNCTXCTL)
	dpdkc.write_reg32(port, TSYNCTXCTL, bit.bor(val, TSYNCTXCTL_EN))
end

local function enableRxTimestampsIgb(port, queue, udpPort, id)
	startTimerIgb(port, id)
	-- l2 rx filter
	dpdkc.write_reg32(port, ETQF_82580_0, bit.bor(
		ETQF_FILTER_ENABLE_82580,
		ETQF_QUEUE_ENABLE_82580,
		ETQF_IEEE_1588_TIME_STAMP,
		eth.TYPE_PTP,
		bit.lshift(queue, 16)
	))
	-- L3 filter not supported :(
	-- enable rx timestamping
	local val = dpdkc.read_reg32(port, TSYNCRXCTL_82580)
	val = bit.bor(val, TSYNCRXCTL_EN)
	val = bit.band(val, bit.bnot(TSYNCRXCTL_TYPE_MASK))
	val = bit.bor(val, bit.lshift(2, TSYNCRXCTL_TYPE_OFFS))
	dpdkc.write_reg32(port, TSYNCRXCTL_82580, val)
end

local function enableTxTimestampsIgb(port, queue, udpPort, id)
	startTimerIgb(port, id)
	local val = dpdkc.read_reg32(port, TSYNCTXCTL_82580)
	dpdkc.write_reg32(port, TSYNCTXCTL_82580, bit.bor(val, TSYNCTXCTL_EN))
end

local function enableRxTimestampsAllIgb(port, queue, id)
	startTimerIgb(port, id)
	local val = dpdkc.read_reg32(port, TSYNCRXCTL_82580)
	val = bit.bor(val, TSYNCRXCTL_EN)
	val = bit.band(val, bit.bnot(TSYNCRXCTL_TYPE_MASK))
	val = bit.bor(val, bit.lshift(bit.lshift(1, 2), TSYNCRXCTL_TYPE_OFFS))
	dpdkc.write_reg32(port, TSYNCRXCTL_82580, val)
	dpdkc.write_reg32(port, SRRCTL_82580[queue], bit.bor(dpdkc.read_reg32(port, SRRCTL_82580[queue]), SRRCTL_TIMESTAMP))
end


-- TODO: implement support for more hardware
local enableFuncs = {
	[device.PCI_ID_X540]	= { enableRxTimestampsIxgbe, enableTxTimestampsIxgbe },
	[device.PCI_ID_82599]	= { enableRxTimestampsIxgbe, enableTxTimestampsIxgbe },
	[device.PCI_ID_82580]	= { enableRxTimestampsIgb, enableTxTimestampsIgb, enableRxTimestampsAllIgb }
}

function rxQueue:enableTimestamps(udpPort)
	udpPort = udpPort or 0
	local id = self.dev:getPciId()
	local f = enableFuncs[id]
	f = f and f[1]
	if not f then
		errorf("RX time stamping on device type %s is not supported", self.dev:getName())
	end
	f(self.id, self.qid, udpPort, id)
end

function rxQueue:enableTimestampsAllPackets()
	local id = self.dev:getPciId()
	local f = enableFuncs[id]
	f = f and f[3]
	if not f then
		errorf("Time stamping all RX packets on device type %s is not supported", self.dev:getName())
	end
	f(self.id, self.qid, id)
end

function txQueue:enableTimestamps(udpPort)
	udpPort = udpPort or 0
	local id = self.dev:getPciId()
	local f = enableFuncs[id]
	f = f and f[2]
	if not f then
		errorf("TX time stamping on device type %s is not supported", self.dev:getName())
	end
	f(self.id, self.qid, udpPort, id)
end

local function getTimestamp(wait, f, ...)
	wait = wait or 0
	repeat
		local ts = f(...)
		if ts then
			return ts
		end
		dpdk.sleepMicros(math.min(10, wait))
		wait = wait - 10
		if not dpdk.running() then
			break
		end
	until wait < 0
	return nil
end

--- Read a TX timestamp from the device.
function txQueue:getTimestamp(wait)
	return getTimestamp(wait, mod.tryReadTxTimestamp, self.id)
end

--- Read a RX timestamp from the device.
function rxQueue:getTimestamp(wait)
	return getTimestamp(wait, mod.tryReadRxTimestamp, self.id)
end

--- Check if the NIC saved a timestamp.
-- @return the PTP sequence number of the timestamped packet, nil otherwise
function dev:hasTimestamp()
	local isIgb = device.get(self.id):getPciId() == device.PCI_ID_82580
	if isIgb then
		if bit.band(dpdkc.read_reg32(self.id, TSYNCRXCTL_82580), TSYNCRXCTL_RXTT) == 0 then
			return nil
		end
		return bswap16(bit.rshift(dpdkc.read_reg32(self.id, RXSATRH_82580), 16))
	else
		if bit.band(dpdkc.read_reg32(self.id, TSYNCRXCTL), TSYNCRXCTL_RXTT) == 0 then
			return nil
		end
		return bswap16(bit.rshift(dpdkc.read_reg32(self.id, RXSATRH), 16))
	end
end

local timestampScales = {
	[device.PCI_ID_X540]	= 6.4,
	[device.PCI_ID_82599]	= 6.4,
	[device.PCI_ID_82580]	= 1, -- ???
}

function dev:getTimestampScale()
	return timestampScales[self:getPciId()] or 1
end

local timeRegisters = {
	[device.PCI_ID_X540]	= { 1, SYSTIMEL, SYSTIMEH, TIMEADJL, TIMEADJH },
	[device.PCI_ID_82599]	= { 1, SYSTIMEL, SYSTIMEH, TIMEADJL, TIMEADJH },
	[device.PCI_ID_82580]	= { 2, SYSTIMEL_82580, SYSTIMEH_82580, TIMEADJL_82580, TIMEADJH_82580 },
}

function mod.syncClocks(dev1, dev2)
	local regs1 = timeRegisters[dev1:getPciId()]
	local regs2 = timeRegisters[dev2:getPciId()]
	if regs1[1] ~= regs2[1] then
		error("NICs incompatible, cannot sync clocks")
	end
	if regs1[2] ~= regs2[2]
		or regs1[3] ~= regs2[3]
		or regs1[4] ~= regs2[4]
		or regs1[5] ~= regs2[5] then
		error("NYI: NICs use different timestamp registers")
	end
	dpdkc.sync_clocks(dev1.id, dev2.id, select(2, unpack(regs1)))
end

function mod.getClockDiff(dev1, dev2)
	return dpdkc.get_clock_difference(dev1.id, dev2.id) * 6.4
end

function mod.readTimestampsSoftware(queue, memory)
	-- TODO: do not allocate this in the luajit heap (limited size)
	-- also: use huge pages
	local numElements = 4096--memory * 1024 * 1024 / 4
	local arr = ffi.new("uint32_t[?]", numElements)
	dpdkc.read_timestamps_software(queue.id, queue.qid, arr, numElements)
	return arr
end


local timestamper = {}
timestamper.__index = timestamper

--- Create a new timestamper.
function mod:newTimestamper(txQueue, rxQueue, mem, udp)
	mem = mem or memory.createMemPool(function(buf)
		-- defaults are good enough for us here
		if udp then
			buf:getUdpPtpPacket():fill{
				ethSrc = txQueue,
			}
		else
			buf:getPtpPacket():fill{
				ethSrc = txQueue,
			}
		end
	end)
	txQueue:enableTimestamps()
	rxQueue:enableTimestamps()
	return setmetatable({
		mem = mem,
		txBufs = mem:bufArray(1),
		rxBufs = mem:bufArray(128),
		txQueue = txQueue,
		rxQueue = rxQueue,
		txDev = txQueue.dev,
		rxDev = rxQueue.dev,
		seq = 1,
		udp = udp,
	}, timestamper)
end

function mod:newUdpTimestamper(txQueue, rxQueue, mem)
	return self:newTimestamper(txQueue, rxQueue, mem, true)
end

--- Try to measure the latency of a single packet.
-- @param pktSize optional, the size of the generated packet, optional, defaults to the smallest possible size
-- @param packetModifier optional, a function that is called with the generated packet, e.g. to modified addresses
-- @param maxWait optional (cannot be the only argument) the time in ms to wait before the packet is assumed to be lost (default = 15)
function timestamper:measureLatency(pktSize, packetModifier, maxWait)
	if type(pktSize) == "function" then -- optional first argument was skipped
		return self:measureLatency(nil, pktSize, packetModifier)
	end
	pktSize = pktSize or self.udp and 76 or 60
	maxWait = (maxWait or 15) / 1000
	self.txBufs:alloc(pktSize)
	local buf = self.txBufs[1]
	buf:enableTimestamps()
	local expectedSeq = self.seq
	self.seq = (self.seq + 1) % 2^16
	if self.udp then
		buf:getUdpPtpPacket().ptp:setSequenceID(expectedSeq)
	else
		buf:getPtpPacket().ptp:setSequenceID(expectedSeq)
	end
	if packetModifier then
		packetModifier(buf)
	end
	if self.udp then
		-- change timestamped UDP port as each packet may be on a different port
		self.rxQueue:enableTimestamps(buf:getUdpPacket().udp:getDstPort())
		self.txBufs:offloadUdpChecksums()
	end
	mod.syncClocks(self.txDev, self.rxDev)
	-- clear any "leftover" timestamps
	if self.rxDev:hasTimestamp() then 
		self.rxQueue:getTimestamp()
	end
	self.txQueue:send(self.txBufs)
	local tx = self.txQueue:getTimestamp(500)
	if tx then
		-- sent was successful, try to get the packet back (assume that it is lost after a given delay)
		local timer = timer:new(maxWait)
		while timer:running() do
			local rx = self.rxQueue:tryRecv(self.rxBufs, 1000)
			local timestampedPkt = self.rxDev:hasTimestamp()
			if not timestampedPkt then
				-- NIC didn't save a timestamp yet, just throw away the packets
				self.rxBufs:freeAll()
			else
				-- received a timestamped packet (not necessarily in this batch)
				-- FIXME: this loop may run into an ugly edge-case where we somehow
				-- lose the timestamped packet during reception (e.g. when this is
				-- running on a shared core and no filters are set), this case isn't handled here
				for i = 1, rx do
					local buf = self.rxBufs[i]
					local seq = (self.udp and buf:getUdpPtpPacket() or buf:getPtpPacket()).ptp:getSequenceID()
					-- not sure if checking :hasTimestamp is worth it
					-- the flag seems to be quite pointless
					if buf:hasTimestamp() and seq == expectedSeq and seq == timestampedPkt then
						-- yay!
						local rxTs = self.rxQueue:getTimestamp() 
						if not rxTs then
							-- can happen if you hotplug cables
							return nil
						end
						local delay = (rxTs - tx) * self.rxDev:getTimestampScale()
						self.rxBufs:freeAll()
						return delay
					elseif buf:hasTimestamp() and seq == timestampedPkt then
						-- we got a timestamp but the wrong sequence number. meh.
						self.rxQueue:getTimestamp() -- clears the register
						-- continue, we may still get our packet :)
					elseif seq == expectedSeq and seq ~= timestampedPkt then
						-- we got our packet back but it wasn't timestamped
						-- we likely ran into the previous case earlier and cleared the ts register too late
						self.rxBufs:freeAll()
						return
					end
				end
			end
		end
		-- looks like our packet got lost :(
		return
	else
		-- uhm, how did this happen? an unsupported NIC should throw an error earlier
		print("Warning: failed to timestamp packet on transmission")
		timer:new(maxWait):wait()
	end
end



return mod

