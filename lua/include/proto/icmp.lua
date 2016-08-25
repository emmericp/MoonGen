------------------------------------------------------------------------
--- @file icmp.lua
--- @brief Internet control message protocol utility.
--- Utility functions for the icmp_header struct
--- defined in \ref headers.lua . \n
--- Includes:
--- - Icmp4 constants
--- - Icmp6 constants
--- - Icmp header utility
--- - Definition of Icmp packets
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

-- FIXME
-- ICMPv6 and ICMPv4 use different values for the same types/codes which causes some complications when handling this with only one header:
-- - getString() does not work for ICMPv6 correctly without some ugly workarounds (basically adding 'ipv4' flags to getString()'s of type/code and header)
-- 	 currently getString() simply does not recognise ICMPv6
-- - Furthermore, packetDump would need a change to pass this flag when calling getString()
-- TODO
-- remove messageBody, instead use new packetCreate with additional header { "ip4", "messageBody" } or similar


---------------------------------------------------------------------------
---- ICMPv4 constants
---------------------------------------------------------------------------

--- Icmp4 protocol constants
local icmp = {}

--- Icmp4 type-code pair: echo reply
icmp.ECHO_REPLY					= { type = 0, code = 0 }
--- Icmp4 type-code pair: echo request
icmp.ECHO_REQUEST 				= { type = 8, code = 0 }

--- Icmp4 type-code pair: destination unreachable - port unreachable
icmp.DST_UNR_PORT_UNR		 	= { type = 3, code = 3 }

--- Icmp4 type-code pair: time exceeded - TTL exceeded
icmp.TIME_EXCEEDED_TTL_EXPIRED	= { type = 11, code = 0 }


--------------------------------------------------------------------------
---- ICMPv6 constants
---------------------------------------------------------------------------

--- Icmp6 protocol constants
local icmp6 = {}

--- Icmp6 type-code pair: echo request
icmp6.ECHO_REQUEST				= { type = 128, code = 0 }
--- Icmp6 type-code pair: echo reply
icmp6.ECHO_REPLY				= { type = 129, code = 0 }


---------------------------------------------------------------------------
---- ICMP header
---------------------------------------------------------------------------

--- Module for icmp_header struct (see \ref headers.lua).
local icmpHeader = {}
icmpHeader.__index = icmpHeader

--- Set the type.
--- @param int Type of the icmp header as 8 bit integer.
function icmpHeader:setType(int)
	int = int or icmp.ECHO_REQUEST.type
	self.type = int
end

--- Retrieve the type.
--- @return Type as 8 bit integer.
function icmpHeader:getType()
	return self.type
end

--- Retrieve the type.
--- does not work for ICMPv6 (ICMPv6 uses different values)
--- @return Type as string.
function icmpHeader:getTypeString()
	local type = self:getType()
	local cleartext = "unknown"

	if type == icmp.ECHO_REPLY.type then
		cleartext = "echo reply"
	elseif type == icmp.ECHO_REQUEST.type then
		cleartext = "echo request"
	elseif type == icmp.DST_UNR_PORT_UNR.type then
		cleartext = "dst. unr."
	elseif type == icmp.TIME_EXCEEDED_TTL_EXPIRED.type then
		cleartext = "time exceeded"
	end

	return format("%s (%s)", type, cleartext)
end

--- Set the code.
--- @param int Code of the icmp header as 8 bit integer.
function icmpHeader:setCode(int)
	int = int or icmp.ECHO_REQUEST.code
	self.code = int
end

--- Retrieve the code.
--- @return Code as 8 bit integer.
function icmpHeader:getCode()
	return self.code
end

--- Retrieve the code.
--- does not work for ICMPv6
--- @return Code as string.
function icmpHeader:getCodeString()
	local type = self:getType()
	local code = self:getCode()
	local cleartext = "unknown"

	if type == icmp.ECHO_REPLY.type then
		cleartext = code == icmp.ECHO_REPLY.code and "correct" or "wrong"
	
	elseif type == icmp.ECHO_REQUEST.type then
		cleartext = code == icmp.ECHO_REQUEST.code and "correct" or "wrong"
	
	elseif type == icmp.DST_UNR_PORT_UNR.type then
		if code == icmp.DST_UNR_PORT_UNR.code then
			cleartext = "port unr."
		end
	
	elseif type == icmp.TIME_EXCEEDED_TTL_EXPIRED.type then
		if code == icmp.TIME_EXCEEDED_TTL_EXPIRED.code then
			cleartext = "ttl expired"
		end
	end

	return format("%s (%s)", code, cleartext)
end


--- Set the checksum.
--- @param int Checksum of the icmp header as 16 bit integer.
function icmpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Calculate the checksum
--- @param len Number of bytes that the checksum will be computed over
function icmpHeader:calculateChecksum(len)
	len = len or sizeof(self)
	self:setChecksum(0)
	self:setChecksum(hton16(checksum(self, len)))
end

--- Retrieve the checksum.
--- @return Checksum as 16 bit integer.
function icmpHeader:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum.
--- @return Checksum as string.
function icmpHeader:getChecksumString()
	return format("0x%04x", self:getChecksum())  
end

--- Set the message body.
--- @param int Message body of the icmp header as TODO.
function icmpHeader:setMessageBody(body)
	body = body or 0
	--self.body.uint8_t = body
end

--- Retrieve the message body.
--- @return Message body as TODO.
function icmpHeader:getMessageBody()
	return self.body
end

--- Retrieve the message body.
--- @return Message body as string TODO.
function icmpHeader:getMessageBodyString()
	return "<some data>"
end

--- Set all members of the icmp header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: Type, Code, Checksum, MessageBody
--- @param pre prefix for namedArgs. Default 'icmp'.
--- @code
--- fill() --- only default values
--- fill{ icmpCode=3 } --- all members are set to default values with the exception of icmpCode
--- @endcode
function icmpHeader:fill(args, pre)
	args = args or {}
	pre = pre or "icmp"

	self:setType(args[pre .. "Type"])
	self:setCode(args[pre .. "Code"])
	self:setChecksum(args[pre .. "Checksum"])
	self:setMessageBody(args[pre .. "MessageBody"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'icmp'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see icmpHeader:fill
function icmpHeader:get(pre)
	pre = pre or "icmp"

	local args = {}
	args[pre .. "Type"] = self:getType()
	args[pre .. "Code"] = self:getCode()
	args[pre .. "Checksum"] = self:getChecksum()
	args[pre .. "MessageBody"] = self:getMessageBody()
	
	return args
end

--- Retrieve the values of all members.
--- Does not work correctly for ICMPv6 packets
--- @return Values in string format.
function icmpHeader:getString()
	return "ICMP type "			.. self:getTypeString() 
			.. " code "		.. self:getCodeString() 
			.. " cksum "	.. self:getChecksumString()
			.. " body "		.. self:getMessageBodyString() .. " "
end

--- Resolve which header comes after this one (in a packet).
--- For instance: in tcp/udp based on the ports.
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'udp', 'icmp', nil)
function icmpHeader:resolveNextHeader()
	return nil
end

--- Change the default values for namedArguments (for fill/get).
--- This can be used to for instance calculate a length value based on the total packet length.
--- See proto/ip4.setDefaultNamedArgs as an example.
--- This function must exist and is only used by packet.fill.
--- @param pre The prefix used for the namedArgs, e.g. 'icmp'
--- @param namedArgs Table of named arguments (see See Also)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see icmpHeader:fill
function icmpHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end


------------------------------------------------------------------------
---- Packets
------------------------------------------------------------------------

--- Cast the packet to an Icmp4 packet 
pkt.getIcmp4Packet = packetCreate("eth", "ip4", "icmp")
--- Cast the packet to an Icmp6 packet 
pkt.getIcmp6Packet = packetCreate("eth", "ip6", "icmp")
--- Cast the packet to either an Icmp4 (nil/true) or Icmp6 (false) packet, depending on the passed boolean.
pkt.getIcmpPacket = function(self, ip4) ip4 = ip4 == nil or ip4 if ip4 then return pkt.getIcmp4Packet(self) else return pkt.getIcmp6Packet(self) end end   


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct icmp_header", icmpHeader)

return icmp, icmp6
