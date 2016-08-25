------------------------------------------------------------------------
--- @file udp.lua
--- @brief User datagram protocol (UDP) utility.
--- Utility functions for udp_header struct
--- defined in \ref headers.lua . \n
--- Includes:
--- - Udp constants
--- - Udp header utility
--- - Definition of Udp packets
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
---- UDP constants 
---------------------------------------------------------------------------

--- Udp protocol constants
local udp = {}

-- TODO move well-known ports somewhere else, those are not only Udp

--- Well known port for Ptp event message
udp.PORT_PTP_EVENTS = 319
--- Well known port for Ptp general message
udp.PORT_PTP_GENERAL_MESSAGES = 320
--- Well known port for VXLAN (RFC7348)
udp.PORT_VXLAN = 4789


---------------------------------------------------------------------------
---- UDP header
---------------------------------------------------------------------------

--- Module for udp_header struct (see \ref headers.lua).
local udpHeader = {}
udpHeader.__index = udpHeader

--- Set the source port.
--- @param int Source port of the udp header as 16 bit integer.
function udpHeader:setSrcPort(int)
	int = int or 1024
	self.src = hton16(int)
end

--- Retrieve the UDP source port.
--- @return Port as 16 bit integer.
function udpHeader:getSrcPort()
	return hton16(self.src)
end

--- Retrieve the UDP source port.
--- @return Port as string.
function udpHeader:getSrcPortString()
	return self:getSrcPort()
end

--- Set the destination port.
--- @param int Destination port of the udp header as 16 bit integer.
function udpHeader:setDstPort(int)
	int = int or 1025
	self.dst = hton16(int)
end

--- Retrieve the UDP destination port.
--- @return Port as 16 bit integer.
function udpHeader:getDstPort()
	return hton16(self.dst)
end

--- Retrieve the UDP destination port.
--- @return Port as string.
function udpHeader:getDstPortString()
	return self:getDstPort()
end

--- Set the length.
--- @param int Length of the udp header plus payload (excluding l2 and l3). 16 bit integer.
function udpHeader:setLength(int)
	int = int or 28 -- with ethernet + IPv4 header -> 64B
	self.len = hton16(int)
end

--- Retrieve the length.
--- @return Length as 16 bit integer.
function udpHeader:getLength()
	return hton16(self.len)
end

--- Retrieve the length.
--- @return Length as string.
function udpHeader:getLengthString()
	return self:getLength()
end

--- Set the checksum.
--- @param int Checksum of the udp header as 16 bit integer.
function udpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Calculate the checksum.
--- @todo FIXME NYI
function udpHeader:calculateChecksum(len)
end

--- Retrieve the checksum.
--- @return Checksum as 16 bit integer.
function udpHeader:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum.
--- @return Checksum as string.
function udpHeader:getChecksumString()
	return format("0x%04x", self:getChecksum())  
end

--- Set all members of the udp header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: udpSrc, udpDst, udpLength, udpChecksum
--- @param pre prefix for namedArgs. Default 'udp'.
--- @code
--- fill() --- only default values
--- fill{ udpSrc=44566, ip6Length=101 } --- all members are set to default values with the exception of udpSrc
--- @endcode
function udpHeader:fill(args, pre)
	args = args or {}
	pre = pre or "udp"

	self:setSrcPort(args[pre .. "Src"])
	self:setDstPort(args[pre .. "Dst"])
	self:setLength(args[pre .. "Length"])
	self:setChecksum(args[pre .. "Checksum"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'udp'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see udpHeader:fill
function udpHeader:get(pre)
	pre = pre or "udp"

	local args = {}
	args[pre .. "Src"] = self:getSrcPort()
	args[pre .. "Dst"] = self:getDstPort()
	args[pre .. "Length"] = self:getLength()
	args[pre .. "Checksum"] = self:getChecksum()

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function udpHeader:getString()
	return "UDP " .. self:getSrcPortString() .. " > " .. self:getDstPortString() .. " len " .. self:getLengthString()
		   .. " cksum " .. self:getChecksumString()
end

-- Maps headers to respective (well knwon) port.
-- This list should be extended whenever a new protocol is added to 'UDP constants'. 
local mapNamePort = {
	ptp = { udp.PORT_PTP_EVENTS, udp.PORT_PTP_GENERAL_MESSAGES },
	vxlan = udp.PORT_VXLAN,
}

--- Resolve which header comes after this one (in a packet).
--- For instance: in tcp/udp based on the ports.
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'udp', 'icmp', nil)
function udpHeader:resolveNextHeader()
	local port = self:getDstPort()
	for name, _port in pairs(mapNamePort) do
		if type(_port) == "table" then
			for _, p in pairs(_port) do
				if port== p then
					return name
				end
			end
		elseif port == _port then
			return name
		end
	end
	return nil
end	

--- Change the default values for namedArguments (for fill/get).
--- This can be used to for instance calculate a length value based on the total packet length.
--- See proto/ip4.setDefaultNamedArgs as an example.
--- This function must exist and is only used by packet.fill.
--- @param pre The prefix used for the namedArgs, e.g. 'udp'
--- @param namedArgs Table of named arguments (see See Also)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see ip4Header:fill
function udpHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	-- set length
	if not namedArgs[pre .. "Length"] and namedArgs["pktLength"] then
		namedArgs[pre .. "Length"] = namedArgs["pktLength"] - accumulatedLength
	end

	-- set dst port
	if not namedArgs[pre .. "Dst"] then
		for name, _port in pairs(mapNamePort) do
			if nextHeader == name then
				namedArgs[pre .. "Dst"] = type(_port) == "table" and _port[1] or _port
				break
			end
		end
	end
	return namedArgs
end

----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

--- Cast the packet to an Udp (IP4) packet
pkt.getUdp4Packet = packetCreate("eth", "ip4", "udp")
--- Cast the packet to an Udp (IP6) packet
pkt.getUdp6Packet = packetCreate("eth", "ip6", "udp") 
--- Cast the packet to an Udp packet, either using IP4 (nil/true) or IP6 (false), depending on the passed boolean.
pkt.getUdpPacket = function(self, ip4) 
	ip4 = ip4 == nil or ip4 
	if ip4 then 
		return pkt.getUdp4Packet(self) 
	else 
		return pkt.getUdp6Packet(self)
	end 
end   


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct udp_header", udpHeader)


return udp
