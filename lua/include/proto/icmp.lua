local ffi = require "ffi"

require "utils"
require "headers"

local eth = require "proto.ethernet"
local ip = require "proto.ip"
local ip6 = require "proto.ip6"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format

-- TODO 
-- ICMPv6 and ICMPv4 use different values for the same types/codes which causes some compliactions when handling this with only one header:
-- - get() always returns values twice with the respective named arguments for both icmpv4/6
-- - getString() does not work for ICMPv6 correctly without some ugly workarounds (basically adding 'ipv4' flags to getString()'s of type/code and header)
-- 	 currently getString() simply does not recognise ICMPv6
-- - Furthermore, dumpPacket would need a change to pass this flag when calling getString()
-- Once this is really needed, better move ICMPv6 to a seperate file (which would result in copying/duplicating 95% of this code)
-- For now those cosmetic issues should not matter.

---------------------------------------------------------------------------
--- ICMPv4 constants
---------------------------------------------------------------------------

local icmp = {}

-- type-code pairs
icmp.ECHO_REPLY					= { type = 0, code = 0 }
icmp.ECHO_REQUEST 				= { type = 8, code = 0 }

icmp.DST_UNR_PORT_UNR		 	= { type = 3, code = 3 }

icmp.TIME_EXCEEDED_TTL_EXPIRED	= { type = 11, code = 0 }


---------------------------------------------------------------------------
--- ICMPv6 constants
---------------------------------------------------------------------------

local icmp6 = {}

icmp6.ECHO_REQUEST				= { type = 128, code = 0 }
icmp6.ECHO_REPLY				= { type = 129, code = 0 }


---------------------------------------------------------------------------
--- ICMP header
---------------------------------------------------------------------------

local icmpHeader = {}
icmpHeader.__index = icmpHeader

--- Set the type.
-- @param int Type of the icmp header as 8 bit integer.
function icmpHeader:setType(int)
	int = int or icmp.ECHO_REQUEST.type
	self.type = int
end

--- Retrieve the type.
-- @return Type as 8 bit integer.
function icmpHeader:getType()
	return self.type
end

--- Retrieve the type.
-- does not work for ICMPv6 (ICMPv6 uses different values)
-- @return Type as string.
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
-- @param int Code of the icmp header as 8 bit integer.
function icmpHeader:setCode(int)
	int = int or icmp.ECHO_REQUEST.code
	self.code = int
end

--- Retrieve the code.
-- @return Code as 8 bit integer.
function icmpHeader:getCode()
	return self.code
end

--- Retrieve the code.
-- does not work for ICMPv6
-- @return Code as string.
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
-- @param int Checksum of the icmp header as 16 bit integer.
function icmpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Calculate the checksum
function icmpHeader:calculateChecksum(len)
	len = len or sizeof(self)
	self:setChecksum(0)
	self:setChecksum(hton16(checksum(self, len)))
end

--- Retrieve the checksum.
-- @return Checksum as 16 bit integer.
function icmpHeader:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum.
-- @return Checksum as string.
function icmpHeader:getChecksumString()
	return format("0x%04x", self:getChecksum())  
end

--- Set the message body.
-- @param int Message body of the icmp header as TODO.
function icmpHeader:setMessageBody(body)
	body = body or 0
	--self.body.uint8_t = body
end

--- Retrieve the message body.
-- @return Message body as TODO.
function icmpHeader:getMessageBody()
	return self.body
end

--- Retrieve the message body.
-- @return Message body as string TODO.
function icmpHeader:getMessageBodyString()
	return "<some data>"
end

--- Set all members of the icmp header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: icmpType, icmpCode, icmpChecksum, icmpMessageBody
-- @usage fill() -- only default values
-- @usage fill{ icmpCode=3 } -- all members are set to default values with the exception of icmpCode
function icmpHeader:fill(args)
	args = args or {}

	self:setType(args.icmpType or args.icmp6Type)
	self:setCode(args.icmpCode or args.icmp6Code)
	self:setChecksum(args.icmpChecksum or args.icmp6Checksum)
	self:setMessageBody(args.icmpMessageBody or args.icmp6MessageBody)
end

--- Retrieve the values of all members.
-- Returns for both ICMP and ICMP6, the user normally knows which one he needs.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see icmpHeader:fill
function icmpHeader:get()
	return { icmpType 			= self:getType(), 
			 icmpCode 			= self:getCode(), 
			 icmpChecksum 		= self:getChecksum(), 
			 icmpMessageBody 	= self:getMessageBody(),
			 -- now the same for icmp6
			 icmp6Type 			= self:getType(), 
			 icmp6Code 			= self:getCode(), 
			 icmp6Checksum 		= self:getChecksum(), 
			 icmp6MessageBody 	= self:getMessageBody() }
end

--- Retrieve the values of all members.
-- Does not work correctly for ICMPv6 packets
-- @return Values in string format.
function icmpHeader:getString()
	return "ICMP type "			.. self:getTypeString() 
			.. " code "		.. self:getCodeString() 
			.. " cksum "	.. self:getChecksumString()
			.. " body "		.. self:getMessageBodyString() .. " "
end


-----------------------------------------------------------------------------
--- ICMPv4 packets
-----------------------------------------------------------------------------

local icmpPacket = {}
icmpPacket.__index = icmpPacket

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set [ip,icmp]Length members of the headers.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ipTTL=100, icmpCode=25 } -- all members are set to default values with the exception of ethSrc, ipTTL and icmpCode
-- @usage fill{ pktLength=64 } -- only default values, all length members are set to the respective values (ipLength)
-- @see etherHeader:fill
-- @see ip4Header:fill
-- @see icmpHeader:fill
function icmpPacket:fill(args)
	args = args or {}
	
	-- calculate length values for all headers
	if args.pktLength then
		args.ipLength = args.pktLength - 14 -- ethernet
	end

	-- change some default values
	args.ipProtocol = ipProtocol or ip.PROTO_ICMP

	-- delete icmpv6 values to circumvent possible conflicts
	args.icmp6Type = nil
	args.icmp6Code = nil
	args.icmp6Checksum = nil
	args.icmp6MessageBody = nil

	self.eth:fill(args)
	self.ip:fill(args)
	self.icmp:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip4Header:get
-- @see icmpHeader:get
function icmpPacket:get()
	return mergeTables(self.eth:get(), self.ip:get(), self.icmp:get())
end

--- Calculate and set the ICMP header checksum for IPv4 packets.
-- @see pkt:offloadIcmpChecksum
function icmpPacket:calculateIcmpChecksum()
	self.icmp:calculateChecksum()
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function icmpPacket:dump(bytes)
	dumpPacket(self, bytes, self.eth, self.ip, self.icmp)
end


-------------------------------------------------------------------------------------------
--- ICMPv6 packet
-------------------------------------------------------------------------------------------

local icmp6Packet = {}
icmp6Packet.__index = icmp6Packet

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set [ip6,icmp]Length members of the headers.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ip6TTL=100, icmpCode=25 } -- all members are set to default values with the exception of ethSrc, ip6TTL and icmpCode
-- @usage fill{ pktLength=64 } -- only default values, all length members are set to the respective values (ip6Length)
-- @see etherHeader:fill
-- @see ip6Header:fill
-- @see icmpHeader:fill
function icmp6Packet:fill(args)
	args = args or {}

	-- calculate length values for all headers
	if args.pktLength then
		args.ip6Length = args.pktLength - (14 + 40) -- ethernet + ip
	end

	-- change some default values for ipv6
	args.ethType = args.ethType or eth.TYPE_IP6
	args.ip6NextHeader = args.ip6NextHeader or ip6.PROTO_ICMP

	-- delete icmpv4 values for no conflicts
	args.icmpType = nil
	args.icmpCode = nil
	args.icmpChecksum = nil
	args.icmpMessageBody = nil
	
	self.eth:fill(args)
	self.ip:fill(args)
	self.icmp:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip4Header:get
-- @see icmpHeader:get
function icmp6Packet:get()
	return mergeTables(self.eth:get(), self.ip:get(), self.icmp:get())
end

--- Calculate and set the ICMP header checksum for IPv6 packets.
-- @see pkt:offloadIcmpChecksum
function icmp6Packet:calculateIcmpChecksum()
	self.icmp:calculateChecksum()
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function icmp6Packet:dump(bytes)
	dumpPacket(self, bytes, self.eth, self.ip, self.icmp)
end


------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct icmp_header", icmpHeader)
ffi.metatype("struct icmp_packet", icmpPacket)
ffi.metatype("struct icmp_v6_packet", icmp6Packet)

return icmp, icmp6
