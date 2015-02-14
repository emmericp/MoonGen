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
-- TODO get/getString

--funcitons for packet
local ptpHeader = {}
ptpHeader.__index = ptpHeader

function ptpHeader:setMessageType(mt)
	mt = mt or ptp.TYPE_SYNC
	self.messageType = mt
end

function ptpHeader:setVersion(v)
	v = v or 0x02 -- version 2
	self.versionPTP = v
end

function ptpHeader:setLength(l)
	l = l or 34 + 10 + 0 -- header, body, suffix
	self.len = hton16(l)
end

function ptpHeader:setDomain(d)
	d = d or 0 -- default domain
	self.domain = d
end

function ptpHeader:setReserved(uint8)
	uint8 = uint8 or 0
	self.reserved = uint8
end

function ptpHeader:setFlags(f)
	f = f or 0 -- no flags
	self.flags = hton16(f)
end

-- TODO find something better for this, 64 bit seems to be trouble for lua?
-- c = { high32bit, low32bit }
function ptpHeader:setCorrection(c)
	c = c or { high=0, low=0 } -- correction offset 0
	self.correction = band(lshift(hton(c.low), 32), hton(c.high))
end

function ptpHeader:setReserved2(uint32)
	uint32 = uint32 or 0
	self.reserved2 = hton(uint32)
end

-- 3 bytes
function ptpHeader:setOui(int)
	int = int or 0
	
	-- X 3 2 1 ->  1 2 3
	self.oui[0] = rshift(band(int, 0xFF0000), 16)
	self.oui[1] = rshift(band(int, 0x00FF00), 8)
	self.oui[2] = band(int, 0x0000FF)
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

function ptpHeader:setNodePort(p)
	p = p or 1
	self.ptpNodePort = hton16(p)
end

function ptpHeader:setSequenceId(s)
	s = s or 0
	self.sequenceId = hton16(s)
end

function ptpHeader:setControl(c)
	c = c or ptp.CONTROL_SYNC
	self.control = c
end

function ptpHeader:setLogMessageInterval(l)
	l = l or 0x7F -- default value
	self.logMessageInterval = l
end

function ptpHeader:fill(args)
	self:setMessageType(args.ptpMessageType)
	self:setVersion(args.ptpVersion)
	self:setLength(args.ptpLength)
	self:setDomain(args.ptpDomain)
	self:setReserved(args.ptpReserved)
	self:setFlags(args.ptpFlags)
	self:setCorrection(args.ptpCorrection)
	self:setReserved2(args.ptpReserved2)
	self:setOui(args.ptpOui)
	self:setUuid(args.ptpUuid)
	self:setNodePort(args.ptpNodePort)
	self:setSequenceId(args.ptpSequenceID)
	self:setControl(args.ptpControl)
	self:setLogMessageInterval(args.ptpLogMessageInterval)
end


-----------------------------------------------------------------------------
---- PTP packet
-----------------------------------------------------------------------------
-- TODO get/dump (in packet.lua extend dump())

local ptpPacket = {}
ptpPacket.__index = ptpPacket

function ptpPacket:fill(args)
	args = args or {}
	
	-- calculate length value for ptp header
	if args.pktLength then
	end
	
	-- change default value for ptp
	args.ethType = args.ethType or eth.TYPE_PTP
	
	self.eth:fill(args)
	self.ptp:fill(args)
end


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct ptp_header", ptpHeader)
ffi.metatype("struct ptp_packet", ptpPacket)

return ptp
