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


---------------------------------------------------------------------------
--- ICMP header
---------------------------------------------------------------------------

local icmpHeader = {}
icmpHeader.__index = icmpHeader

--- Set the type.
-- @param int Type of the icmp header as 8 bit integer.
function icmpHeader:setType(int)
	int = int or 0 -- TODO
	self.type = int
end

--- Retrieve the type.
-- @return Type as 8 bit integer.
function icmpHeader:getType()
	return self.type
end

--- Retrieve the type.
-- @return Type as string.
function icmpHeader:getTypeString()
	return self:getType() -- TODO
end

--- Set the code.
-- @param int Code of the icmp header as 8 bit integer.
function icmpHeader:setCode(int)
	int = int or 0 -- TODO
	self.code = int
end

--- Retrieve the code.
-- @return Code as 8 bit integer.
function icmpHeader:getCode()
	return self.code
end

--- Retrieve the code.
-- @return Code as string.
function icmpHeader:getCodeString()
	return self:getCode() -- TODO
end


--- Set the checksum.
-- @param int Checksum of the icmp header as 16 bit integer.
function icmpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
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
	--self.body = body
end

--- Retrieve the message body.
-- @return Message body as TODO.
function icmpHeader:getMessageBody()
	return self.body
end

--- Retrieve the message body.
-- @return Message body as string.
function icmpHeader:getMessageBodyString()
	return "<some data>"-- format("0x%x", self:getMessageBody()) -- TODO return as hexdump
end

--- Set all members of the icmp header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: icmpType, icmpCode, icmpChecksum, icmpMessageBody
-- @usage fill() -- only default values
-- @usage fill{ icmpCode=3 } -- all members are set to default values with the exception of icmpCode
function icmpHeader:fill(args)
	args = args or {}

	self:setType(args.icmpType)
	self:setCode(args.icmpCode)
	self:setChecksum(args.icmpChecksum)
	self:setMessageBody(args.icmpMessageBody)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see icmpHeader:fill
function icmpHeader:get()
	return { icmpType=self:getType(), 
			 icmpCode=self:getCode(), 
			 icmpChecksum=self:getChecksum(), 
			 icmpMessageBody=self:getMessageBody() }
end

--- Retrieve the values of all members.
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

	args.ipProtocol = ipProtocol or ip.PROTO_ICMP

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
-- TODO i didn't find any dpdk bitmask for ICMP, calculate manually is a must?
-- @see pkt:offloadIcmpChecksum
function icmpPacket:calculateIcmpChecksum()
	self.icmp:setChecksum()
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
-- TODO
-- @see pkt:offloadIcmpChecksum
function icmp6Packet:calculateIcmpChecksum()
	self.icmp:setChecksum()
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
