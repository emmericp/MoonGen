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
--- UDP header
---------------------------------------------------------------------------

local udpHeader = {}
udpHeader.__index = udpHeader

--- Set the source port.
-- @param int Source port of the udp header as 16 bit integer.
function udpHeader:setSrcPort(int)
	int = int or 1024
	self.src = hton16(int)
end

--- Retrieve the UDP source port.
-- @return Port as 16 bit integer.
function udpHeader:getSrcPort()
	return hton16(self.src)
end

--- Retrieve the UDP source port.
-- @return Port as string.
function udpHeader:getSrcPortString()
	return self:getSrcPort()
end

--- Set the destination port.
-- @param int Destination port of the udp header as 16 bit integer.
function udpHeader:setDstPort(int)
	int = int or 1025
	self.dst = hton16(int)
end

--- Retrieve the UDP destination port.
-- @return Port as 16 bit integer.
function udpHeader:getDstPort()
	return hton16(self.dst)
end

--- Retrieve the UDP destination port.
-- @return Port as string.
function udpHeader:getDstPortString()
	return self:getDstPort()
end

--- Set the length.
-- @param int Length of the udp header plus payload (excluding l2 and l3). 16 bit integer.
function udpHeader:setLength(int)
	int = int or 28 -- with ethernet + IPv4 header -> 64B
	self.len = hton16(int)
end

--- Retrieve the length.
-- @return Length as 16 bit integer.
function udpHeader:getLength()
	return hton16(self.len)
end

--- Retrieve the length.
-- @return Length as string.
function udpHeader:getLengthString()
	return self:getLength()
end

--- Set the checksum.
-- @param int Checksum of the udp header as 16 bit integer.
function udpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Retrieve the checksum.
-- @return Checksum as 16 bit integer.
function udpHeader:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum.
-- @return Checksum as string.
function udpHeader:getChecksumString()
	return format("0x%04x", self:getChecksum())  
end

--- Set all members of the udp header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: udpSrc, udpDst, udpLength, udpChecksum
-- @usage fill() -- only default values
-- @usage fill{ udpSrc=44566, ip6Length=101 } -- all members are set to default values with the exception of udpSrc and udpLength
function udpHeader:fill(args)
	args = args or {}

	self:setSrcPort(args.udpSrc)
	self:setDstPort(args.udpDst)
	self:setLength(args.udpLength)
	self:setChecksum(args.udpChecksum)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see udpHeader:fill
function udpHeader:get()
	return { udpSrc=self:getSrcPort(), udpDst=self:getDstPort(), udpLength=self:getLength(), udpChecksum=self:getChecksum() }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function udpHeader:getString()
	return "UDP " .. self:getSrcPortString() .. " > " .. self:getDstPortString() .. " len " .. self:getLengthString()
		   .. " cksum " .. self:getChecksumString()
end


-----------------------------------------------------------------------------
--- UDPv4 packets
-----------------------------------------------------------------------------

local udpPacket = {}
udpPacket.__index = udpPacket

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set [ip,udp]Length members of the headers.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ipTTL=100, udpDst=2500 } -- all members are set to default values with the exception of ethSrc, ipTTL and udpDst
-- @usage fill{ pktLength=64 } -- only default values, all length members are set to the respective values (ipLength, udpLength)
-- @see etherHeader:fill
-- @see ip4Header:fill
-- @see udpHeader:fill
function udpPacket:fill(args)
	args = args or {}
	
	-- calculate length values for all headers
	if args.pktLength then
		args.ipLength = args.ipLength or args.pktLength - 14 -- ethernet

		ipHeaderBytes = (args.ipHeaderLength or 5) * 4 -- ip_h can have variable size
		args.udpLength = args.udpLength or args.pktLength - (14 + ipHeaderBytes) -- ethernet + ip
	end

	self.eth:fill(args)
	self.ip:fill(args)
	self.udp:fill(args)
end

-- TODO: ugly place for this but required
-- @scholzd: how to fix this?
function udpPacket:setLength(len)
	local ipLen = len - 14
	local udpLen = len - 14 - 20
	self.ip:setLength(ipLen)
	self.udp:setLength(udpLen)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip4Header:get
-- @see udpHeader:get
function udpPacket:get()
	return mergeTables(self.eth:get(), self.ip:get(), self.udp:get())
end

--- Calculate and set the UDP header checksum for IPv4 packets.
-- Not implemented as it is optional.
-- If possible use checksum offloading instead.
-- @see pkt:offloadUdpChecksum
function udpPacket:calculateUdpChecksum()
	-- optional, so don't do it
	self.udp:setChecksum()
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function udpPacket:dump(bytes)
	dumpPacket(self, bytes, self.eth, self.ip, self.udp)
end


-------------------------------------------------------------------------------------------
--- UDPv6 packet
-------------------------------------------------------------------------------------------

local udp6Packet = {}
udp6Packet.__index = udp6Packet

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set [ip6,udp]Length members of the headers.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ip6TTL=100, udpDst=2500 } -- all members are set to default values with the exception of ethSrc, ip6TTL and udpDst
-- @usage fill{ pktLength=64 } -- only default values, all length members are set to the respective values (ip6Length, udpLength)
-- @see etherHeader:fill
-- @see ip6Header:fill
-- @see udpHeader:fill
function udp6Packet:fill(args)
	args = args or {}

	-- calculate length values for all headers
	if args.pktLength then
		args.ip6Length = args.ip6Length or args.pktLength - (14 + 40) -- ethernet + ip
		args.udpLength = args.udpLength or args.pktLength - (14 + 40) -- ethernet + ip
	end

	-- change some default values for ipv6
	args.ethType = args.ethType or eth.TYPE_IP6
	args.udpLength = args.udpLength or 8

	self.eth:fill(args)
	self.ip:fill(args)
	self.udp:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip4Header:get
-- @see udpHeader:get
function udp6Packet:get()
	return mergeTables(self.eth:get(), self.ip:get(), self.udp:get())
end

--- Calculate and set the UDP header checksum for IPv6 packets.
-- Not implemented (todo).
-- If possible use checksum offloading instead.
-- @see pkt:offloadUdpChecksum
function udp6Packet:calculateUdpChecksum()
	-- TODO as it is mandatory for IPv6 UDP packets
	self.udp:setChecksum()
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function udp6Packet:dump(bytes)
	dumpPacket(self, bytes, self.eth, self.ip, self.udp)
end


------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct udp_header", udpHeader)
ffi.metatype("struct udp_packet", udpPacket)
ffi.metatype("struct udp_v6_packet", udp6Packet)
