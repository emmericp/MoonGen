------------------------------------------------------------------------
--- @file ptp.lua
--- @brief Precision time protocol (PTP) utility.
--- Utility functions for the ptp_header struct
--- defined in \ref headers.lua . \n
--- Includes:
--- - PTP constants
--- - PTP header utility
--- - Definition of PTP packets
------------------------------------------------------------------------

local ffi = require "ffi"
local pkt = require "packet"

require "utils"
require "headers"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format


---------------------------------------------------------------------------
---- PTP constants
---------------------------------------------------------------------------

--- Ptp protocol constants
local ptp = {}

-- Message type: sync
ptp.TYPE_SYNC = 0
-- Message type: delay req
ptp.TYPE_DELAY_REQ = 1
-- Message type: follow up
ptp.TYPE_FOLLOW_UP = 8
-- Message type: delay resp
ptp.TYPE_DELAY_RESP = 9

-- Message control: sync
ptp.CONTROL_SYNC = 0
-- Message control: delay req
ptp.CONTROL_DELAY_REQ = 1
-- Message control: follow up
ptp.CONTROL_FOLLOW_UP = 2
-- Message control: delay resp
ptp.CONTROL_DELAY_RESP = 3


---------------------------------------------------------------------------
---- PTP header
---------------------------------------------------------------------------

--- Module for ptp_header struct (see \ref headers.lua).
local ptpHeader = {}
ptpHeader.__index = ptpHeader

--- Set the message type.
--- @param mt Message type as 8 bit integer.
function ptpHeader:setMessageType(mt)
	mt = mt or ptp.TYPE_SYNC
	self.messageType = mt
end

--- Retrieve the message type.
--- @return Message type as 8 bit integer.
function ptpHeader:getMessageType()
	return self.messageType
end

--- Retrieve the message type.
--- @return Message type in string format.
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

--- Set the version.
--- @param v Version as 8 bit integer.
function ptpHeader:setVersion(v)
	v = v or 0x02 -- version 2
	self.versionPTP = v
end

--- Retrieve the version.
--- @return Version as 8 bit integer.
function ptpHeader:getVersion()
	return self.versionPTP
end

--- Retrieve the version.
--- @return Version in string format.
function ptpHeader:getVersionString()
	return self:getVersion()
end

--- Set the length.
--- @param l Length as 16 bit integer.
function ptpHeader:setLength(l)
	l = l or 34 + 10 + 0 -- header, body, suffix
	self.len = hton16(l)
end

--- Retrieve the length.
--- @return Length as 16 bit integer.
function ptpHeader:getLength()
	return hton16(self.len)
end

--- Retrieve the length.
--- @return Length in string format.
function ptpHeader:getLengthString()
	return self:getLength()
end

--- Set the domain.
--- @param d Domain as 8 bit integer.
function ptpHeader:setDomain(d)
	d = d or 0 -- default domain
	self.domain = d
end

--- Retrieve the domain.
--- @return Domain as 8 bit integer.
function ptpHeader:getDomain()
	return self.domain
end

--- Retrieve the domain.
--- @return Domain in string format.
function ptpHeader:getDomainString()
	return self:getDomain()
end

--- Set the reserved field.
--- @param uint8 Reserved as 8 bit integer.
function ptpHeader:setReserved(uint8)
	uint8 = uint8 or 0
	self.reserved = uint8
end

--- Retrieve the reserved field.
--- @return Reserved field as 8 bit integer.
function ptpHeader:getReserved()
	return self.reserved
end

--- Retrieve the reserved field.
--- @return Reserved field in string format.
function ptpHeader:getReservedString()
	return format("0x%02x", self:getReserved())
end

--- Set the flags.
--- @param f Flags as 16 bit integer.
function ptpHeader:setFlags(f)
	f = f or 0 -- no flags
	self.flags = hton16(f)
end

--- Retrieve the flags.
--- @return Flags as 16 bit integer.
function ptpHeader:getFlags()
	return hton16(self.flags)
end

--- Retrieve the flags.
--- @return Flags in string format.
function ptpHeader:getFlagsString()
	return format("0x%04x", self:getFlags())
end

--- Set the correction field.
--- @param c Correction field as table of two 32 bit integers { high, low }.
--- @todo find something better for this, 64 bit seems to be trouble for lua?
--- c = { high32bit, low32bit }
function ptpHeader:setCorrection(c)
	c = c or { high=0, low=0 } -- correction offset 0
	self.correction[0] = hton(c.low)
	self.correction[1] = hton(c.high)
end

--- Retrieve the correction field.
--- @return Correction field as table two 32 bit integers { high, low }.
function ptpHeader:getCorrection()
	return { high = hton(self.correction[1]), low = hton(self.correction[0]) }
end

--- Retrieve the correction field.
--- @return Correction field in string format.
function ptpHeader:getCorrectionString()
	local t = self:getCorrection()
	return format("0x%08x%08x", t.high, t.low)
end

--- Set the reserved2 field.
--- @param uint32 Reserved2 as 32 bit integer.
function ptpHeader:setReserved2(uint32)
	uint32 = uint32 or 0
	self.reserved2 = hton(uint32)
end

--- Retrieve the reserved2 field.
--- @return Reserved2 field as 32 bit integer.
function ptpHeader:getReserved2()
	return hton(self.reserved2)
end

--- Retrieve the reserved2 field.
--- @return Reserved2 field in string format.
function ptpHeader:getReserved2String()
	return format("0x%08x", self:getReserved2())
end

--- Set the oui.
--- @param int Oui as 24 bit integer.
function ptpHeader:setOui(int)
	int = int or 0

	-- X 3 2 1 ->  1 2 3
	self.oui[0] = rshift(band(int, 0xFF0000), 16)
	self.oui[1] = rshift(band(int, 0x00FF00), 8)
	self.oui[2] = band(int, 0x0000FF)
end

--- Retrieve the oui.
--- @return Oui as 24 bit integer.
function ptpHeader:getOui()
	return bor(lshift(self.oui[0], 16), bor(lshift(self.oui[1], 8), self.oui[2]))
end

--- Retrieve the oui.
--- @return Oui in string format.
function ptpHeader:getOuiString()
	return format("0x%06x", self:getOui())
end

--- Set the uuid.
--- @param int Uuis as table of two integers { high, low }, high as 8 bit integer and low as 32 bit integer.
--- @todo same problem as with correction field
--- c = { high8bit, low32bit }
function ptpHeader:setUuid(int)
	int = int or { high=0, low=0 }

	-- X X X 1 5 4 3 2 -> 1 2 3 4 5
	self.uuid[0] = int.high
	self.uuid[1] = rshift(band(int.low, 0xFF000000), 24)
	self.uuid[2] = rshift(band(int.low, 0x00FF0000), 16)
	self.uuid[3] = rshift(band(int.low, 0x0000FF00), 8)
	self.uuid[4] = 		  band(int.low, 0x000000FF)
end

--- Retrieve the Uuid.
--- @return Uuid as table of two integers { high, low }, high is an 8 bit integer, low 32 bit integer.
function ptpHeader:getUuid()
	local t = {}
	t.high = self.uuid[0] 
	t.low = bor(lshift(self.uuid[1], 24), bor(lshift(self.uuid[2], 16), bor(lshift(self.uuid[3], 8), self.uuid[4])))
	return t
end

--- Retrieve the Uuid.
--- @return Uuid in string format.
function ptpHeader:getUuidString()
	local t = self:getUuid()
	return format("0x%02x%08x", t.high, t.low)
end

--- Set the node port.
--- @param p Node port as 16 bit integer.
function ptpHeader:setNodePort(p)
	p = p or 1
	self.ptpNodePort = hton16(p)
end

--- Retrieve the node port.
--- @return Node port as 16 bit integer.
function ptpHeader:getNodePort()
	return hton16(self.ptpNodePort)
end

--- Retrieve the node port.
--- @return Node port in string format.
function ptpHeader:getNodePortString()
	return self:getNodePort()
end

--- Set the sequence ID.
--- @param s Sequence ID as 16 bit integer.
function ptpHeader:setSequenceID(s)
	s = s or 0
	self.sequenceId = hton16(s)
end

--- Retrieve the sequence ID.
--- @return Sequence ID as 16 bit integer.
function ptpHeader:getSequenceID()
	return hton16(self.sequenceId)
end

--- Retrieve the sequence ID.
--- @return Sequence ID in string format.
function ptpHeader:getSequenceIDString()
	return self:getSequenceID()
end

--- Set the control field.
--- @param c Control field as 8 bit integer.
function ptpHeader:setControl(c)
	c = c or ptp.CONTROL_SYNC
	self.control = c
end

--- Retrieve the control field.
--- @return Control field as 8 bit integer.
function ptpHeader:getControl()
	return self.control
end

--- Retrieve the control field.
--- @return Control field in string format.
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

--- Set the log message interval.
--- @param l Log message interval as 8 bit integer.
function ptpHeader:setLogMessageInterval(l)
	l = l or 0x7F -- default value
	self.logMessageInterval = l
end

--- Retrieve the log message interval.
--- @return Log message interval as 8 bit integer.
function ptpHeader:getLogMessageInterval()
	return self.logMessageInterval
end

--- Retrieve the log message interval.
--- @return Log message interval in string format.
function ptpHeader:getLogMessageIntervalString()
	return self:getLogMessageInterval()
end

--- Set all members of the ip header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: MessageType, Version, Length, Domain, Reserved, Flags, Correction, Reserved2, Oui, Uuid, NodePort, SequenceID, Control, LogMessageInterval 
--- @param pre prefix for namedArgs. Default 'ptp'.
--- @code
--- fill() --- only default values
--- fill{ ptpLenght=123, ipTTL=100 } --- all members are set to default values with the exception of ptpLength
--- @endcode
function ptpHeader:fill(args, pre)
	args = args or {}
	pre = pre or "ptp"

	self:setMessageType(args[pre .. "MessageType"])
	self:setVersion(args[pre .. "Version"])
	self:setLength(args[pre .. "Length"])
	self:setDomain(args[pre .. "Domain"])
	self:setReserved(args[pre .. "Reserved"])
	self:setFlags(args[pre .. "Flags"])
	self:setCorrection(args[pre .. "Correction"])
	self:setReserved2(args[pre .. "Reserved2"])
	self:setOui(args[pre .. "Oui"])
	self:setUuid(args[pre .. "Uuid"])
	self:setNodePort(args[pre .. "NodePort"])
	self:setSequenceID(args[pre .. "SequenceID"])
	self:setControl(args[pre .. "Control"])
	self:setLogMessageInterval(args[pre .. "LogMessageInterval"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'ptp'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see ptpHeader:fill
function ptpHeader:get(pre)
	pre = pre or "ptp"

	local args = {}
	args[pre .. "MessageTyp"] = self:getMessageType()
	args[pre .. "Version"] = self:getVersion()
	args[pre .. "Length"] = self:getLength()
	args[pre .. "Domain"] = self:getDomain()
	args[pre .. "Reserved"] = self:getReserved()
	args[pre .. "Flags"] = self:getFlags()
	args[pre .. "Correction"] = self:getCorrection()
	args[pre .. "Reserved2"] = self:getReserved2()
	args[pre .. "Oui"] = self:getOui()
	args[pre .. "Uuid"] = self:getUuid()
	args[pre .. "NodePort"] = self:getNodePort()
	args[pre .. "SequenceID"] = self:getSequenceID()
	args[pre .. "Control"] = self:getControl()
	args[pre .. "LogMessageInterval"] = self:getLogMessageInterval()

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
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

--- Resolve which header comes after this one (in a packet).
--- For instance: in tcp/udp based on the ports.
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'udp', 'icmp', nil)
function ptpHeader:resolveNextHeader()
	return nil
end

--- Change the default values for namedArguments (for fill/get).
--- This can be used to for instance calculate a length value based on the total packet length.
--- See proto/ip4.setDefaultNamedArgs as an example.
--- This function must exist and is only used by packet.fill.
--- @param pre The prefix used for the namedArgs, e.g. 'ptp'
--- @param namedArgs Table of named arguments (see See Also)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @see ptpHeader:fill
function ptpHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	-- set length
	if not namedArgs[pre .. "Length"] and namedArgs["pktLength"] then
		namedArgs[pre .. "Length"] = namedArgs["pktLength"] - accumulatedLength
	end
	return namedArgs
end


---------------------------------------------------------------------------------
---- Packets
---------------------------------------------------------------------------------

--- Cast the packet to a layer 2 Ptp packet 
pkt.getPtpPacket = packetCreate("eth", "ptp")
--- Cast the packet to a Ptp over Udp (IP4) packet
pkt.getUdpPtpPacket = packetCreate("eth", "ip4", "udp", "ptp")


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct ptp_header", ptpHeader)

return ptp
