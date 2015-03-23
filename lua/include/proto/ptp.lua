local ffi = require "ffi"

require "utils"
require "headers"

local eth = require "proto.ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format


---------------------------------------------------------------------------
---- PTP constants
---------------------------------------------------------------------------

local ptp = {}

-- message type
ptp.TYPE_SYNC = 0
ptp.TYPE_DELAY_REQ = 1
ptp.TYPE_FOLLOW_UP = 8
ptp.TYPE_DELAY_RESP = 9

-- control
ptp.CONTROL_SYNC = 0
ptp.CONTROL_DELAY_REQ = 1
ptp.CONTROL_FOLLOW_UP = 2
ptp.CONTROL_DELAY_RESP = 3


---------------------------------------------------------------------------
---- PTP header
---------------------------------------------------------------------------

--funcitons for packet
local ptpHeader = {}
ptpHeader.__index = ptpHeader

function ptpHeader:setMessageType(mt)
	mt = mt or ptp.TYPE_SYNC
	self.messageType = mt
end

function ptpHeader:getMessageType()
	return self.messageType
end

function ptpHeader:getMessageTypeString()
	local type = self:getMessageType()
	local cleartext = ""
	
	if type == ptp.TYPE_SYNC then
		cleartext = "(sync)"
	elseif type == ptp.TYPE_DELAY_REQ then
		cleartext = "(delay req)"
	elseif type == ptp.TYPE_FOLLOW_UP then
		cleartext = "(follow up)"
	elseif type == ptp.TYPE_DELAY_RESP then
		cleartext = "(delay resp)"
	else
		cleartext = "(unknown)"
	end

	return format("0x%02x %s", type, cleartext)
end

function ptpHeader:setVersion(v)
	v = v or 0x02 -- version 2
	self.versionPTP = v
end

function ptpHeader:getVersion()
	return self.versionPTP
end

function ptpHeader:getVersionString()
	return self:getVersion()
end

function ptpHeader:setLength(l)
	l = l or 34 + 10 + 0 -- header, body, suffix
	self.len = hton16(l)
end

function ptpHeader:getLength()
	return hton16(self.len)
end

function ptpHeader:getLengthString()
	return self:getLength()
end

function ptpHeader:setDomain(d)
	d = d or 0 -- default domain
	self.domain = d
end

function ptpHeader:getDomain()
	return self.domain
end

function ptpHeader:getDomainString()
	return self:getDomain()
end

function ptpHeader:setReserved(uint8)
	uint8 = uint8 or 0
	self.reserved = uint8
end

function ptpHeader:getReserved()
	return self.reserved
end

function ptpHeader:getReservedString()
	return format("0x%02x", self:getReserved())
end

function ptpHeader:setFlags(f)
	f = f or 0 -- no flags
	self.flags = hton16(f)
end

function ptpHeader:getFlags()
	return hton16(self.flags)
end

function ptpHeader:getFlagsString()
	return format("0x%04x", self:getFlags())
end

-- TODO find something better for this, 64 bit seems to be trouble for lua?
-- c = { high32bit, low32bit }
function ptpHeader:setCorrection(c)
	c = c or { high=0, low=0 } -- correction offset 0
	self.correction[0] = hton(c.low)
	self.correction[1] = hton(c.high)
end

function ptpHeader:getCorrection()
	return { high = hton(self.correction[1]), low = hton(self.correction[0]) }
end

function ptpHeader:getCorrectionString()
	local t = self:getCorrection()
	return format("0x%08x%08x", t.high, t.low)
end

function ptpHeader:setReserved2(uint32)
	uint32 = uint32 or 0
	self.reserved2 = hton(uint32)
end

function ptpHeader:getReserved2()
	return hton(self.reserved2)
end

function ptpHeader:getReserved2String()
	return format("0x%08x", self:getReserved2())
end

-- 3 bytes
function ptpHeader:setOui(int)
	int = int or 0

	-- X 3 2 1 ->  1 2 3
	self.oui[0] = rshift(band(int, 0xFF0000), 16)
	self.oui[1] = rshift(band(int, 0x00FF00), 8)
	self.oui[2] = band(int, 0x0000FF)
end

function ptpHeader:getOui()
	return bor(lshift(self.oui[0], 16), bor(lshift(self.oui[1], 8), self.oui[2]))
end

function ptpHeader:getOuiString()
	return format("0x%06x", self:getOui())
end

-- TODO same problem as above
-- c = { high8bit, low32bit }
-- 5 bytes
function ptpHeader:setUuid(int)
	int = int or { high=0, low=0 }

	-- X X X 1 5 4 3 2 -> 1 2 3 4 5
	self.uuid[0] = int.high
	self.uuid[1] = rshift(band(int.low, 0xFF000000), 24)
	self.uuid[2] = rshift(band(int.low, 0x00FF0000), 16)
	self.uuid[3] = rshift(band(int.low, 0x0000FF00), 8)
	self.uuid[4] = 		  band(int.low, 0x000000FF)
end

function ptpHeader:getUuid()
	local t = {}
	t.high = self.uuid[0] 
	t.low = bor(lshift(self.uuid[1], 24), bor(lshift(self.uuid[2], 16), bor(lshift(self.uuid[3], 8), self.uuid[4])))
	return t
end

function ptpHeader:getUuidString()
	local t = self:getUuid()
	return format("0x%02x%08x", t.high, t.low)
end

function ptpHeader:setNodePort(p)
	p = p or 1
	self.ptpNodePort = hton16(p)
end

function ptpHeader:getNodePort()
	return hton16(self.ptpNodePort)
end

function ptpHeader:getNodePortString()
	return self:getNodePort()
end

function ptpHeader:setSequenceID(s)
	s = s or 0
	self.sequenceId = hton16(s)
end

function ptpHeader:getSequenceID()
	return hton16(self.sequenceId)
end

function ptpHeader:getSequenceIDString()
	return self:getSequenceID()
end

function ptpHeader:setControl(c)
	c = c or ptp.CONTROL_SYNC
	self.control = c
end

function ptpHeader:getControl()
	return self.control
end

function ptpHeader:getControlString()
	local type = self:getControl()
	local cleartext = ""
	
	if type == ptp.CONTROL_SYNC then
		cleartext = "(sync)"
	elseif type == ptp.CONTROL_DELAY_REQ then
		cleartext = "(delay req)"
	elseif type == ptp.CONTROL_FOLLOW_UP then
		cleartext = "(follow up)"
	elseif type == ptp.CONTROL_DELAY_RESP then
		cleartext = "(delay resp)"
	else
		cleartext = "(unknown)"
	end

	return format("0x%02x %s", type, cleartext)
end

function ptpHeader:setLogMessageInterval(l)
	l = l or 0x7F -- default value
	self.logMessageInterval = l
end

function ptpHeader:getLogMessageInterval()
	return self.logMessageInterval
end

function ptpHeader:getLogMessageIntervalString()
	return self:getLogMessageInterval()
end

function ptpHeader:fill(args)
	self:setMessageType(args.ptpMessageType)
	self:setVersion(args.ptpVersion or 2)
	self:setLength(args.ptpLength)
	self:setDomain(args.ptpDomain)
	self:setReserved(args.ptpReserved)
	self:setFlags(args.ptpFlags)
	self:setCorrection(args.ptpCorrection)
	self:setReserved2(args.ptpReserved2)
	self:setOui(args.ptpOui)
	self:setUuid(args.ptpUuid)
	self:setNodePort(args.ptpNodePort)
	self:setSequenceID(args.ptpSequenceID)
	self:setControl(args.ptpControl)
	self:setLogMessageInterval(args.ptpLogMessageInterval)
end

function ptpHeader:get()
	return { 
		ptpMessageTyp			= self:getMessageType(),
		ptpVersion				= self:getVersion(),
		ptpLength				= self:getLength(),
		ptpDomain				= self:getDomain(),
		ptpReserved				= self:getReserved(),
		ptpFlags				= self:getFlags(),
		ptpCorrection			= self:getCorrection(),
		ptpReserved2			= self:getReserved2(),
		ptpOui					= self:getOui(),
		ptpUuid					= self:getUuid(),
		ptpNodePort				= self:getNodePort(),
		ptpSequenceID			= self:getSequenceID(),
		ptpControl				= self:getControl(),
		ptpLogMessageInterval	= self:getLogMessageInterval()
	}
end

function ptpHeader:getString()
	return "PTP typ " .. self:getMessageTypeString()
		.. " ver " .. self:getVersionString()
		.. " len " .. self:getLengthString()
		.. " dom " .. self:getDomainString()
		.. " res " .. self:getReservedString()
		.. " fla " .. self:getFlagsString()
		.. " cor " .. self:getCorrectionString()
		.. " res " .. self:getReserved2String()
		.. " oui " .. self:getOuiString()
		.. " uuid " .. self:getUuidString()
		.. " nod " .. self:getNodePortString()
		.. " seq " .. self:getSequenceIDString()
		.. " ctrl " .. self:getControlString()
		.. " log " .. self:getLogMessageIntervalString()
end


-----------------------------------------------------------------------------
---- PTP packet
-----------------------------------------------------------------------------

local ptpPacket = {}
ptpPacket.__index = ptpPacket

function ptpPacket:fill(args)
	args = args or {}
	
	-- calculate length value for ptp header
	if args.pktLength then
		args.ptpLength = args.ptpLength or args.pktLength - 14 -- ethernet, assuming rest of packet is ptp header and body (no other payload)
	end
	
	-- change default value for ptp
	args.ethType = args.ethType or eth.TYPE_PTP
	
	self.eth:fill(args)
	self.ptp:fill(args)
end

function ptpPacket:get()
	return mergeTables(self.eth:get(), self.ptp:get())
end

function ptpPacket:dump(bytes)
	dumpPacket(self, bytes, self.eth, self.ptp)
end


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct ptp_header", ptpHeader)
ffi.metatype("struct ptp_packet", ptpPacket)

return ptp
