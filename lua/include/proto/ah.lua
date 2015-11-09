------------------------------------------------------------------------
--- @file ah.lua
--- @brief AH utility.
--- Utility functions for the ah_header structs 
--- defined in \ref headers.lua . \n
--- Includes:
--- - AH constants
--- - IPsec ICV
--- - AH header utility
--- - Definition of AH packets
------------------------------------------------------------------------

local ffi = require "ffi"
local pkt = require "packet"

require "headers"

---------------------------------------------------------------------------
---- ah constants 
---------------------------------------------------------------------------

local ah = {}

-------------------------------------------------------------------------------------
---- IPsec IV -> see proto/esp.lua
-------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------
---- IPsec ICV
-------------------------------------------------------------------------------------

local ipsecICV = {}
ipsecICV.__index = ipsecICV
local ipsecICVType = ffi.typeof("union ipsec_icv")

--- Set the IPsec ICV.
--- @param iv IPsec ICV in 'union ipsec_icv' format.
function ipsecICV:set(icv)
	-- For AH hw offload the ICV has to be zero
	local offload_icv = ffi.new("union ipsec_icv")
	offload_icv.uint32[0] = 0x0
	offload_icv.uint32[1] = 0x0
	offload_icv.uint32[2] = 0x0
	offload_icv.uint32[3] = 0x0

	icv = icv or offload_icv
	self.uint32[0] = hton(icv.uint32[3])
	self.uint32[1] = hton(icv.uint32[2])
	self.uint32[2] = hton(icv.uint32[1])
	self.uint32[3] = hton(icv.uint32[0])
end

--- Retrieve the IPsec ICV
--- @return ICV in 'union ipsec_icv' format.
function ipsecICV:get()
	local icv = ipsecICVType()
	icv.uint32[0] = hton(self.uint32[3])
	icv.uint32[1] = hton(self.uint32[2])
	icv.uint32[2] = hton(self.uint32[1])
	icv.uint32[3] = hton(self.uint32[0])
	return icv
end

--- Get the IPsec string.
--- @param icv IPsec ICV in string format.
function ipsecICV:getString(doByteSwap)
	doByteSwap = doByteSwap or false
	if doByteSwap then
		self = self:get()
	end

	return ("0x%08x%08x%08x%08x"):format(self.uint32[3], self.uint32[2], self.uint32[1], self.uint32[0])
end

---------------------------------------------------------------------------
---- ah header
---------------------------------------------------------------------------

local ahHeader = {}
ahHeader.__index = ahHeader

--- Set the SPI.
--- @param int SPI of the ah header as A bit integer.
function ahHeader:setSPI(int)
	int = int or 0
	self.spi = hton(int)
end

--- Retrieve the SPI.
--- @return SPI as A bit integer.
function ahHeader:getSPI()
	return hton(self.spi)
end

--- Retrieve the SPI as string.
--- @return SPI as string.
function ahHeader:getSPIString()
	return self:getSPI()
end

--- Set the SQN.
--- @param int SQN of the ah header as A bit integer.
function ahHeader:setSQN(int)
	int = int or 0
	self.sqn = hton(int)
end

--- Retrieve the SQN.
--- @return SQN as A bit integer.
function ahHeader:getSQN()
	return hton(self.sqn)
end

--- Retrieve the SQN as string.
--- @return SQN as string.
function ahHeader:getSQNString()
	return self:getSQN()
end

--- Set the IV.
--- @param int IV of the ah header as 'union ipsec_iv'.
function ahHeader:setIV(iv)
	self.iv:set(iv)
end

--- Retrieve the IV.
--- @return SPI as 'union ipsec_iv'.
function ahHeader:getIV()
	return self.iv:get()
end

--- Retrieve the IV as string.
--- @return IV as string.
function ahHeader:getIVString()
	return self.iv:getString(true)
end

--- Set the ICV.
--- @param int ICV of the ah header as...
function ahHeader:setICV(icv)
	self.icv:set(icv)
end

--- Retrieve the ICV.
--- @return SPI as...
function ahHeader:getICV()
	return self.icv:get()
end

--- Retrieve the ICV as string.
--- @return ICV as string.
function ahHeader:getICVString()
	return self.icv:getString(true)
end

--- Set the Next Header.
--- @param int Next Header of the ah header as A bit integer.
function ahHeader:setNextHeader(int)
	int = int or 0
	self.nextHeader = int
end

--- Retrieve the Next Header.
--- @return Next Header as A bit integer.
function ahHeader:getNextHeader()
	return self.nextHeader
end

--- Retrieve the Next Header as string.
--- @return Next Header as string.
function ahHeader:getNextHeaderString()
	return self:getNextHeader()
end

--- Set the Length.
--- @param int Length of the ah header as A bit integer.
function ahHeader:setLength(int)
	-- The AH header has a fixed length for AES-GMAC
	-- (cf. chapter 16.5.1 "AH Formats" of X540 Datasheet)
	-- Authentication header length in 32-bit Dwords units, minus 2,
	-- such as for AES-128 its value is 7 for IPv4 and 8 for IPv6.
	int = int or 7 -- IPv4: 7 = (9-2)
	self.len = int
end

--- Retrieve the Length.
--- @return Length as A bit integer.
function ahHeader:getLength()
	return self.len
end

--- Retrieve the Length as string.
--- @return Length as string.
function ahHeader:getLengthString()
	return self:getLength()
end

--- Set all members of the ah header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: ahSPI, ahSQN, ahIV, ahICV
--- @param pre prefix for namedArgs. Default 'ah'.
--- @usage fill() -- only default values
--- @usage fill{ ahXYZ=1 } -- all members are set to default values with the exception of ahXYZ, ...
function ahHeader:fill(args, pre)
	args = args or {}
	pre = pre or "ah"

	self:setSPI(args[pre .. "SPI"])
	self:setSQN(args[pre .. "SQN"])
	self:setIV(args[pre .. "IV"])
	self:setICV(args[pre .. "ICV"])
	self:setNextHeader(args[pre .. "NextHeader"])
	self:setLength(args[pre .. "Length"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'ah'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see ahHeader:fill
function ahHeader:get(pre)
	pre = pre or "ah"

	local args = {}
	args[pre .. "SPI"] = self:getSPI() 
	args[pre .. "SQN"] = self:getSQN()
	args[pre .. "IV"] = self:getIV()
	args[pre .. "ICV"] = self:getICV()
	args[pre .. "NextHeader"] = self:getNextHeader()
	args[pre .. "Length"] = self:getLength()

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function ahHeader:getString()
	return "AH spi " .. self:getSPIString() .. " sqn " .. self:getSQNString() .. " iv " .. self:getIVString() .. " icv " .. self:getICVString() .. " next_hdr " .. self:getNextHeader() .. " len " .. self:getLength()
end

--- Resolve which header comes after this one (in a packet)
--- For instance: in tcp/udp based on the ports
--- This function must exist and is only used when get/dump is executed on 
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'eth', 'ip4', nil)
function ahHeader:resolveNextHeader()
	return nil
	--TODO: return self:getNextHeader()
end	

--- Change the default values for namedArguments (for fill/get)
--- This can be used to for instance calculate a length value based on the total packet length
--- See proto/ip4.setDefaultNamedArgs as an example
--- This function must exist and is only used by packet.fill
--- @param pre The prefix used for the namedArgs, e.g. 'ah'
--- @param namedArgs Table of named arguments (see See more)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see ahHeader:fill
function ahHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

-- Ah4 packets should not be shorter than 70 bytes (cf. x540 datasheet page 308: SECP field)
pkt.getAh4Packet = packetCreate("eth", "ip4", "ah")
-- Ah6 packets should not be shorter than 94 bytes (cf. x540 datasheet page 308: SECP field)
pkt.getAh6Packet = nil --packetCreate("eth", "ip6", "ah6") --TODO: AH6 needs to be implemented
pkt.getAhPacket = function(self, ip4) ip4 = ip4 == nil or ip4 if ip4 then return pkt.getAh4Packet(self) else return pkt.getAh6Packet(self) end end

------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

--ffi.metatype("union ipsec_iv", ipsecIV)
ffi.metatype("union ipsec_icv", ipsecICV)
ffi.metatype("struct ah_header", ahHeader)

return ah
