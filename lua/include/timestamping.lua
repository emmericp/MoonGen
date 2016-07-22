---------------------------------
--- @file timestamping.lua
--- @brief Timestamping ...
--- @todo TODO docu
---------------------------------

-- FIXME: this file is ugly because it doesn't abstract anything properly
local mod = {}

local ffi		= require "ffi"
local dpdkc		= require "dpdkc"
local dpdk		= require "dpdk"
local device	= require "device"
local eth		= require "proto.ethernet"
local memory	= require "memory"
local timer		= require "timer"
local log		= require "log"
local filter	= require "filter"

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

-- registers, mostly X710/XL710-specific
local PRTTSYN_CTL0      = 0x001E4200
local PRTTSYN_CTL1      = 0x00085020
local PRTTSYN_RXTIME_H  = {}
local PRTTSYN_RXTIME_L  = {}
for i = 0, 3 do
	PRTTSYN_RXTIME_H[i] = 0x00085040 + 0x20 * i
	PRTTSYN_RXTIME_L[i] = 0x000850C0 + 0x20 * i
end
local PRTTSYN_STAT_1    = 0x00085140
local PRTTSYN_INC_L     = 0x001E4040
local PRTTSYN_INC_H     = 0x001E4060
local PRTTSYN_TIME_L    = 0x001E4100
local PRTTSYN_TIME_H    = 0x001E4120
local PRTTSYN_ADJ       = 0x001E4280
local PRTTSYN_ADJ_DUMMY = 0x00083100 -- actually GL_FWRESETCNT (RO)
local PRTTSYN_TXTIME_L  = 0x001E41C0
local PRTTSYN_TXTIME_H  = 0x001E41E0
local PRTTSYN_STAT_0    = 0x001E4220

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
local PRTTSYN_CTL0_TSYNENA  = bit.lshift(1, 31)

local PRTTSYN_CTL1_TSYNENA  = bit.lshift(1, 31)
local PRTTSYN_CTL1_TSYNTYPE_OFFS = 24
local PRTTSYN_CTL1_TSYNTYPE_MASK = bit.lshift(3, PRTTSYN_CTL1_TSYNTYPE_OFFS)
local PRTTSYN_CTL1_UDP_ENA_OFFS = 26
local PRTTSYN_CTL1_UDP_ENA_MASK = bit.lshift(3, PRTTSYN_CTL1_UDP_ENA_OFFS)

local PRTTSYN_STAT_1_RXT0 = 1
local PRTTSYN_STAT_1_RXT1 = bit.lshift(1, 1)
local PRTTSYN_STAT_1_RXT2 = bit.lshift(1, 2)
local PRTTSYN_STAT_1_RXT3 = bit.lshift(1, 3)
local PRTTSYN_STAT_1_RXT_ALL = 0xf

local PRTTSYN_STAT_0_TXTIME = bit.lshift(1, 4)
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

-- constants
local I40E_PTP_10GB_INCVAL  = 0x0333333333ULL

--- @deprecated
function mod.fillL2Packet(buf, seq)
	seq = seq or (((3 * 255) + 2) * 255 + 1) * 255
	buf.pkt_len = 60
	buf.data_len = 60
	buf:getPtpPacket():fill{
		ptpSequenceID = seq
	}
	buf.ol_flags = bit.bor(buf.ol_flags, dpdk.PKT_TX_IEEE1588_TMST)
end

--- @deprecated
function mod.readSeq(buf)
	if buf.pkt_len < 4 then
	  return nil
	end
	return buf:getPtpPacket().ptp:getSequenceID()
end

-- TODO these functions should also use the upper 32 bit...

--- try to read a tx timestamp if one is available, returns -1 if no timestamp is available
function mod.tryReadTxTimestamp(port)
	local id = device.get(port):getPciId()
	if id == device.PCI_ID_X710 or id == device.PCI_ID_XL710 or id == device.PCI_ID_XL710Q1 then
		local val = dpdkc.read_reg32(port, PRTTSYN_STAT_0)
		if bit.band(val, PRTTSYN_STAT_0_TXTIME) == 0 then
			return nil
		end
		local low = dpdkc.read_reg32(port, PRTTSYN_TXTIME_L)
		local high = dpdkc.read_reg32(port, PRTTSYN_TXTIME_H)
		return low
	elseif id == device.PCI_ID_82580 then
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

function mod.tryReadRxTimestamp(port, timesync)
	local id = device.get(port):getPciId()
	if id == device.PCI_ID_X710 or id == device.PCI_ID_XL710 or id == device.PCI_ID_XL710Q1 then
		local rtxindex = bit.lshift(1, timesync)
		if bit.band(dpdkc.read_reg32(port, PRTTSYN_STAT_1), rtxindex) == 0 then
 			return nil
 		end
		local low = dpdkc.read_reg32(port, PRTTSYN_RXTIME_L[timesync])
		local high = dpdkc.read_reg32(port, PRTTSYN_RXTIME_H[timesync])
		return low
	elseif id == device.PCI_ID_82580 then
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

local function cleanTimestamp(dev, rxQueue)
	local id = device.get(dev.id):getPciId()
	if id == device.PCI_ID_X710 or id == device.PCI_ID_XL710 or id == device.PCI_ID_XL710Q1 then
		local stats = dpdkc.read_reg32(dev.id, PRTTSYN_STAT_1)
		if bit.band(stats, PRTTSYN_STAT_1_RXT_ALL) ~= 0 then
			for i = 0, 3 do
				rxQueue:getTimestamp(nil, i)
			end
		end
	elseif devTimeStamp then
		-- clear any "leftover" timestamps
		if dev:hasTimestamp() then
			self.rxQueue:getTimestamp()
		end
	end
end


local function startTimerI40e(port, id)
	-- start system timer
	if id == device.PCI_ID_X710 or id == device.PCI_ID_XL710 or id == device.PCI_ID_XL710Q1 then
		dpdkc.write_reg32(port, PRTTSYN_INC_L, bit.band(I40E_PTP_10GB_INCVAL, 0xFFFFFFFF))
		dpdkc.write_reg32(port, PRTTSYN_INC_H, bit.rshift(I40E_PTP_10GB_INCVAL, 32))
	else -- should not happen
		log:fatal("Unsupported i40e device %s", device.getDeviceName(port))
	end
end

local function startTimerIxgbe(port, id)
	-- start system timer, this differs slightly between the two currently supported ixgbe-chips
	if id == device.PCI_ID_X540 then
		dpdkc.write_reg32(port, TIMEINCA, 1)
	elseif id == device.PCI_ID_82599 or id == device.PCI_ID_X520 or id == device.PCI_ID_X520_T2 then
		dpdkc.write_reg32(port, TIMINCA, bit.bor(2, bit.lshift(2, TIMINCA_IP_OFFS)))
	else -- should not happen
		log:fatal("Unsupported ixgbe device %s", device.getDeviceName(port))
	end
end

local function startTimerIgb(port, id)
	if id == device.PCI_ID_82580
	or id == device.PCI_ID_I350 then
		-- start the timer
		dpdkc.write_reg32(port, TIMINCA_82580, 1)
		dpdkc.write_reg32(port, TSAUXC, bit.band(dpdkc.read_reg32(port, TSAUXC), bit.bnot(TSAUXC_DISABLE)))

	else
		log:fatal("Unsupported igb device %s", device.getDeviceName(port))
	end
end

local function enableRxTimestampsI40e(port, queue, udpPort, id)
	-- clear timesync registers
	dpdkc.read_reg32(port, PRTTSYN_STAT_0)
	dpdkc.read_reg32(port, PRTTSYN_RXTIME_L[0])
	dpdkc.read_reg32(port, PRTTSYN_RXTIME_L[1])
	dpdkc.read_reg32(port, PRTTSYN_RXTIME_L[2])
	dpdkc.read_reg32(port, PRTTSYN_RXTIME_L[3])
	device.get(port):l2Filter(eth.TYPE_PTP, queue)
	-- start the timer
	startTimerI40e(port, id)
	-- enable rx timestamping
	local val0 = dpdkc.read_reg32(port, PRTTSYN_CTL0)
	dpdkc.write_reg32(port, PRTTSYN_CTL0, bit.bor(val0, PRTTSYN_CTL0_TSYNENA))
	local val1 = dpdkc.read_reg32(port, PRTTSYN_CTL1)
	val1 = bit.bor(val1, PRTTSYN_CTL1_TSYNENA)
	val1 = bit.band(val1, bit.bnot(PRTTSYN_CTL1_TSYNTYPE_MASK))
	val1 = bit.bor(val1, bit.lshift(2, PRTTSYN_CTL1_TSYNTYPE_OFFS))
	val1 = bit.band(val1, bit.bnot(PRTTSYN_CTL1_UDP_ENA_MASK))
	val1 = bit.bor(val1, bit.lshift(3, PRTTSYN_CTL1_UDP_ENA_OFFS))
	dpdkc.write_reg32(port, PRTTSYN_CTL1, val1)
end

local function enableTxTimestampsI40e(port, queue, udpPort, id)
	-- clear timesync registers
	dpdkc.read_reg32(port, PRTTSYN_STAT_0)
	dpdkc.read_reg32(port, PRTTSYN_TXTIME_H)
	-- start the timer
	startTimerI40e(port, id)
	-- enable tx timestamping
	local val0 = dpdkc.read_reg32(port, PRTTSYN_CTL0)
	dpdkc.write_reg32(port, PRTTSYN_CTL0, bit.bor(val0, PRTTSYN_CTL0_TSYNENA))
	local val1 = dpdkc.read_reg32(port, PRTTSYN_CTL1)
	dpdkc.write_reg32(port, PRTTSYN_CTL1, bit.bor(val1, PRTTSYN_CTL1_TSYNENA))
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
	[device.PCI_ID_XL710]	= { enableRxTimestampsI40e, enableTxTimestampsI40e },
	[device.PCI_ID_XL710Q1]	= { enableRxTimestampsI40e, enableTxTimestampsI40e },
	[device.PCI_ID_X710]	= { enableRxTimestampsI40e, enableTxTimestampsI40e },
	[device.PCI_ID_X540]	= { enableRxTimestampsIxgbe, enableTxTimestampsIxgbe },
	[device.PCI_ID_X520]	= { enableRxTimestampsIxgbe, enableTxTimestampsIxgbe },
	[device.PCI_ID_X520_T2]	= { enableRxTimestampsIxgbe, enableTxTimestampsIxgbe },
	[device.PCI_ID_82599]	= { enableRxTimestampsIxgbe, enableTxTimestampsIxgbe },
	[device.PCI_ID_82580]	= { enableRxTimestampsIgb, enableTxTimestampsIgb, enableRxTimestampsAllIgb },
	[device.PCI_ID_I350]	= { nil, nil, enableRxTimestampsAllIgb },
}

function rxQueue:enableTimestamps(udpPort)
	udpPort = udpPort or 0
	local id = self.dev:getPciId()
	local f = enableFuncs[id]
	f = f and f[1]
	if not f then
		log:fatal("RX time stamping on device type %s is not supported", self.dev:getName())
	end
	f(self.id, self.qid, udpPort, id)
end

function rxQueue:enableTimestampsAllPackets()
	local id = self.dev:getPciId()
	local f = enableFuncs[id]
	f = f and f[3]
	if not f then
		log:fatal("Time stamping all RX packets on device type %s is not supported", self.dev:getName())
	end
	f(self.id, self.qid, id)
end

function txQueue:enableTimestamps(udpPort)
	udpPort = udpPort or 0
	local id = self.dev:getPciId()
	local f = enableFuncs[id]
	f = f and f[2]
	if not f then
		log:fatal("TX time stamping on device type %s is not supported", self.dev:getName())
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
function rxQueue:getTimestamp(wait, timesync)
	return getTimestamp(wait, mod.tryReadRxTimestamp, self.id, timesync)
end

--- Check if the NIC saved a timestamp.
--- @return the PTP sequence number of the timestamped packet, -1 if the NIC doesn't support capturing it, nil if no timestamp is available
function dev:hasTimestamp()
	local id = device.get(self.id):getPciId()
	if id == device.PCI_ID_X710 or id == device.PCI_ID_XL710 or id == device.PCI_ID_XL710Q1 then
		local stats = dpdkc.read_reg32(self.id, PRTTSYN_STAT_1)
		return bit.band(stats, PRTTSYN_STAT_1_RXT_ALL) ~= 0 and -1 or nil
	elseif id  == device.PCI_ID_82580 then
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

function dev:supportsTimesync()
	local id = self:getPciId()
	return id == device.PCI_ID_X710 or id == device.PCI_ID_XL710 or id == device.PCI_ID_XL710Q1
end

local timestampScales = {
	[device.PCI_ID_XL710]	= 1,
	[device.PCI_ID_XL710Q1]	= 1,
	[device.PCI_ID_X710]	= 1,
	[device.PCI_ID_X540]	= 6.4,
	[device.PCI_ID_X520]	= 6.4,
	[device.PCI_ID_82599]	= 6.4,
	[device.PCI_ID_82580]	= 1,
}

function dev:getTimestampScale()
	return timestampScales[self:getPciId()] or 1
end

local timeRegisters = {
	[device.PCI_ID_XL710]	= { 1, PRTTSYN_TIME_L, PRTTSYN_TIME_H, PRTTSYN_ADJ, PRTTSYN_ADJ_DUMMY },
	[device.PCI_ID_XL710Q1]	= { 1, PRTTSYN_TIME_L, PRTTSYN_TIME_H, PRTTSYN_ADJ, PRTTSYN_ADJ_DUMMY },
	[device.PCI_ID_X710]	= { 1, PRTTSYN_TIME_L, PRTTSYN_TIME_H, PRTTSYN_ADJ, PRTTSYN_ADJ_DUMMY },
	[device.PCI_ID_X540]	= { 2, SYSTIMEL, SYSTIMEH, TIMEADJL, TIMEADJH },
	[device.PCI_ID_X520]    = { 2, SYSTIMEL, SYSTIMEH, TIMEADJL, TIMEADJH },
	[device.PCI_ID_82599]	= { 2, SYSTIMEL, SYSTIMEH, TIMEADJL, TIMEADJH },
	[device.PCI_ID_82580]	= { 3, SYSTIMEL_82580, SYSTIMEH_82580, TIMEADJL_82580, TIMEADJH_82580 }, }

function mod.syncClocks(dev1, dev2)
	local regs1 = timeRegisters[dev1:getPciId()]
	local regs2 = timeRegisters[dev2:getPciId()]
	if regs1[1] ~= regs2[1] then
		log:fatal("NICs incompatible, cannot sync clocks")
	end
	if regs1[2] ~= regs2[2]
		or regs1[3] ~= regs2[3]
		or regs1[4] ~= regs2[4]
		or regs1[5] ~= regs2[5] then
		log:fatal("NYI: NICs use different timestamp registers")
	end
	dpdkc.sync_clocks(dev1.id, dev2.id, select(2, unpack(regs1)))
end

function mod.getClockDiff(dev1, dev2)
	local regs1 = timeRegisters[dev1:getPciId()]
	local regs2 = timeRegisters[dev2:getPciId()]
	if regs1[1] ~= regs2[1] then
		log:fatal("NICs incompatible, cannot sync clocks")
	end
	if regs1[2] ~= regs2[2]
		or regs1[3] ~= regs2[3] then
		log:fatal("NYI: NICs use different timestamp registers")
	end
	local timestampScale = timestampScales[dev1:getPciId()]
	return dpdkc.get_clock_difference(dev1.id, dev2.id, regs1[2], regs1[3]) * timestampScale
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
--- A NIC can only be used by one thread at a time due to clock synchronization.
--- Best current pratice is to use only one timestamping thread to avoid problems.
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
		useTimesync = rxQueue.dev:supportsTimesync(),
	}, timestamper)
end

--- See newTimestamper()
function mod:newUdpTimestamper(txQueue, rxQueue, mem)
	return self:newTimestamper(txQueue, rxQueue, mem, true)
end

--- Try to measure the latency of a single packet.
--- @param pktSize optional, the size of the generated packet, optional, defaults to the smallest possible size
--- @param packetModifier optional, a function that is called with the generated packet, e.g. to modified addresses
--- @param maxWait optional (cannot be the only argument) the time in ms to wait before the packet is assumed to be lost (default = 15)
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
	cleanTimestamp(self.rxDev, self.rxQueue)
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
					local timesync = self.useTimesync and buf:getTimesync() or 0
					local seq = (self.udp and buf:getUdpPtpPacket() or buf:getPtpPacket()).ptp:getSequenceID()
					if buf:hasTimestamp() and seq == expectedSeq and (seq == timestampedPkt or timestampedPkt == -1) then
						-- yay!
						local rxTs = self.rxQueue:getTimestamp(nil, timesync) 
						if not rxTs then
							-- can happen if you hotplug cables
							return nil
						end
						local delay = (rxTs - tx) * self.rxDev:getTimestampScale()
						self.rxBufs:freeAll()
						return delay
					elseif buf:hasTimestamp() and (seq == timestampedPkt or timestampedPkt == -1) then
						-- we got a timestamp but the wrong sequence number. meh.
						self.rxQueue:getTimestamp(nil, timesync) -- clears the register
						-- continue, we may still get our packet :)
					elseif seq == expectedSeq and (seq ~= timestampedPkt and timestampedPkt ~= -1) then
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
		log:warn("Failed to timestamp packet on transmission")
		timer:new(maxWait):wait()
	end
end



return mod

