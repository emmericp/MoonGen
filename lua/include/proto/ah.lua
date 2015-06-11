local ffi = require "ffi"
local pkt = require "packet"

require "headers"


---------------------------------------------------------------------------
--- ah constants 
---------------------------------------------------------------------------

local ah = {}

-------------------------------------------------------------------------------------
--- IPsec IV
-------------------------------------------------------------------------------------

local ipsecIV = {}
ipsecIV.__index = ipsecIV
local ipsecIVType = ffi.typeof("union ipsec_iv")

--- Retrieve the IPsec IV.
--- Set the IPsec IV.
-- @param iv IPsec IV in 'union ipsec_iv' format.
function ipsecIV:set(iv)
	self.uint32[0] = hton(iv.uint32[1])
	self.uint32[1] = hton(iv.uint32[0])
end

-- @return IV in 'union ipsec_iv' format.
function ipsecIV:get()
	local iv = ipsecIVType()
	iv.uint32[0] = hton(self.uint32[1])
	iv.uint32[1] = hton(self.uint32[0])
	return iv
end

--- Get the IPsec string.
-- @param iv IPsec IV in string format.
function ipsecIV:getString(doByteSwap)
	doByteSwap = doByteSwap or false
	if doByteSwap then
		self = self:get()
	end

	return ("%08x%08x"):format(self.uint32[0], self.uint32[1])
end

-------------------------------------------------------------------------------------
--- IPsec ICV
-------------------------------------------------------------------------------------

local ipsecICV = {}
ipsecICV.__index = ipsecICV
local ipsecICVType = ffi.typeof("union ipsec_icv")

--- Retrieve the IPsec ICV.
--- Set the IPsec ICV.
-- @param iv IPsec ICV in 'union ipsec_icv' format.
function ipsecICV:set(icv)
	self.uint32[0] = hton(icv.uint32[3])
	self.uint32[1] = hton(icv.uint32[2])
	self.uint32[2] = hton(icv.uint32[1])
	self.uint32[3] = hton(icv.uint32[0])
end

-- @return ICV in 'union ipsec_icv' format.
function ipsecICV:get()
	local icv = ipsecICVType()
	icv.uint32[0] = hton(self.uint32[3])
	icv.uint32[1] = hton(self.uint32[2])
	icv.uint32[2] = hton(self.uint32[1])
	icv.uint32[3] = hton(self.uint32[0])
	return icv
end

--- Get the IPsec string.
-- @param icv IPsec ICV in string format.
function ipsecICV:getString(doByteSwap)
	doByteSwap = doByteSwap or false
	if doByteSwap then
		self = self:get()
	end

	return ("%08x%08x%08x%08x"):format(self.uint32[0], self.uint32[1], self.uint32[2], self.uint32[3])
end

---------------------------------------------------------------------------
--- ah header
---------------------------------------------------------------------------

local ahHeader = {}
ahHeader.__index = ahHeader

--- Set the SPI.
-- @param int SPI of the ah header as A bit integer.
function ahHeader:setSPI(int)
	int = int or 0
	self.spi = hton(int)
end

--- Retrieve the SPI.
-- @return SPI as A bit integer.
function ahHeader:getSPI()
	return hton(self.spi)
end

--- Retrieve the SPI as string.
-- @return SPI as string.
function ahHeader:getSPIString()
	return self:getSPI()
end

--- Set the SQN.
-- @param int SQN of the ah header as A bit integer.
function ahHeader:setSQN(int)
	int = int or 0
	self.sqn = hton(int)
end

--- Retrieve the SQN.
-- @return SQN as A bit integer.
function ahHeader:getSQN()
	return hton(self.sqn)
end

--- Retrieve the SQN as string.
-- @return SQN as string.
function ahHeader:getSQNString()
	return self:getSQN()
end

--- Set the IV.
-- @param int IV of the ah header as 'union ipsec_iv'.
function ahHeader:setIV(iv)
	self.iv:set(iv)
end

--- Retrieve the IV.
-- @return SPI as 'union ipsec_iv'.
function ahHeader:getIV()
	return self.iv:get()
end

--- Retrieve the IV as string.
-- @return IV as string.
function ahHeader:getIVString()
	return self.iv:getString(true)
end

--- Set the ICV.
-- @param int ICV of the ah header as...
function ahHeader:setICV(icv)
	--TODO:
	self.iv:set(icv)
end

--- Retrieve the ICV.
-- @return SPI as...
function ahHeader:getICV()
	--TODO:
	return self.icv:get()
end

--- Retrieve the ICV as string.
-- @return ICV as string.
function ahHeader:getICVString()
	--TODO:
	return self.icv:getString(true)
end

--- Set all members of the ah header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ahSPI, ahSQN, ahIV, ahICV
-- @param pre prefix for namedArgs. Default 'ah'.
-- @usage fill() -- only default values
-- @usage fill{ ahXYZ=1 } -- all members are set to default values with the exception of ahXYZ, ...
function ahHeader:fill(args, pre)
	args = args or {}
	pre = pre or "ah"

	self:setSPI(args[pre .. "SPI"])
	self:setSQN(args[pre .. "SQN"])
	self:setIV(args[pre .. "IV"])
	self:setICV(args[pre .. "ICV"])
end

--- Retrieve the values of all members.
-- @param pre prefix for namedArgs. Default 'ah'.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see ahHeader:fill
function ahHeader:get(pre)
	pre = pre or "ah"

	local args = {}
	args[pre .. "SPI"] = self:getSPI() 
	args[pre .. "SQN"] = self:getSQN()
	args[pre .. "IV"] = self:getIV()
	args[pre .. "ICV"] = self:getICV()

	return args
end

--- Retrieve the values of all members.
-- @return Values in string format.
function ahHeader:getString()
	--TODO: next_hdr ...
	return "AH spi " .. self:getSPIString() .. " sqn " .. self:getSQNString() .. " iv " .. self:getIVString() .. " icv " .. self:getICVString()
end

--- Resolve which header comes after this one (in a packet)
-- For instance: in tcp/udp based on the ports
-- This function must exist and is only used when get/dump is executed on 
-- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
-- @return String next header (e.g. 'eth', 'ip4', nil)
function ahHeader:resolveNextHeader()
	--TODO:
	return nil
end	

--- Change the default values for namedArguments (for fill/get)
-- This can be used to for instance calculate a length value based on the total packet length
-- See proto/ip4.setDefaultNamedArgs as an example
-- This function must exist and is only used by packet.fill
-- @param pre The prefix used for the namedArgs, e.g. 'ah'
-- @param namedArgs Table of named arguments (see See more)
-- @param nextHeader The header following after this header in a packet
-- @param accumulatedLength The so far accumulated length for previous headers in a packet
-- @see ahHeader:fill
function ahHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

---------------------------------------------------------------------------
--- ah6 header
---------------------------------------------------------------------------

local ah6Header = {}
ah6Header.__index = ah6Header

--- Set the SPI.
-- @param int SPI of the ah header as A bit integer.
function ah6Header:setSPI(int)
	int = int or 0
	self.spi = hton(int)
end

--- Retrieve the SPI.
-- @return SPI as A bit integer.
function ah6Header:getSPI()
	return hton(self.spi)
end

--- Retrieve the SPI as string.
-- @return SPI as string.
function ah6Header:getSPIString()
	return self:getSPI()
end

--- Set the SQN.
-- @param int SQN of the ah header as A bit integer.
function ah6Header:setSQN(int)
	int = int or 0
	self.sqn = hton(int)
end

--- Retrieve the SQN.
-- @return SQN as A bit integer.
function ah6Header:getSQN()
	return hton(self.sqn)
end

--- Retrieve the SQN as string.
-- @return SQN as string.
function ah6Header:getSQNString()
	return self:getSQN()
end

--- Set the IV.
-- @param int IV of the ah header as 'union ipsec_iv'.
function ah6Header:setIV(iv)
	self.iv:set(iv)
end

--- Retrieve the IV.
-- @return SPI as 'union ipsec_iv'.
function ah6Header:getIV()
	return self.iv:get()
end

--- Retrieve the IV as string.
-- @return IV as string.
function ah6Header:getIVString()
	return self.iv:getString(true)
end

--- Set the ICV.
-- @param int ICV of the ah header as...
function ah6Header:setICV(icv)
	--TODO:
	self.iv:set(icv)
end

--- Retrieve the ICV.
-- @return SPI as...
function ah6Header:getICV()
	--TODO:
	return self.icv:get()
end

--- Retrieve the ICV as string.
-- @return ICV as string.
function ah6Header:getICVString()
	--TODO:
	return self.icv:getString(true)
end

--- Set all members of the ah header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ahSPI, ahSQN, ahIV, ahICV
-- @param pre prefix for namedArgs. Default 'ah'.
-- @usage fill() -- only default values
-- @usage fill{ ahXYZ=1 } -- all members are set to default values with the exception of ahXYZ, ...
function ah6Header:fill(args, pre)
	args = args or {}
	pre = pre or "ah"

	self:setSPI(args[pre .. "SPI"])
	self:setSQN(args[pre .. "SQN"])
	self:setIV(args[pre .. "IV"])
	self:setICV(args[pre .. "ICV"])
end

--- Retrieve the values of all members.
-- @param pre prefix for namedArgs. Default 'ah'.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see ah6Header:fill
function ah6Header:get(pre)
	pre = pre or "ah"

	local args = {}
	args[pre .. "SPI"] = self:getSPI() 
	args[pre .. "SQN"] = self:getSQN()
	args[pre .. "IV"] = self:getIV()
	args[pre .. "ICV"] = self:getICV()

	return args
end

--- Retrieve the values of all members.
-- @return Values in string format.
function ah6Header:getString()
	--TODO: next_hdr ...
	return "AH spi " .. self:getSPIString() .. " sqn " .. self:getSQNString() .. " iv " .. self:getIVString() .. " icv " .. self:getICVString()
end

--- Resolve which header comes after this one (in a packet)
-- For instance: in tcp/udp based on the ports
-- This function must exist and is only used when get/dump is executed on 
-- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
-- @return String next header (e.g. 'eth', 'ip4', nil)
function ah6Header:resolveNextHeader()
	--TODO:
	return nil
end	

--- Change the default values for namedArguments (for fill/get)
-- This can be used to for instance calculate a length value based on the total packet length
-- See proto/ip4.setDefaultNamedArgs as an example
-- This function must exist and is only used by packet.fill
-- @param pre The prefix used for the namedArgs, e.g. 'ah'
-- @param namedArgs Table of named arguments (see See more)
-- @param nextHeader The header following after this header in a packet
-- @param accumulatedLength The so far accumulated length for previous headers in a packet
-- @see ah6Header:fill
function ah6Header:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

----------------------------------------------------------------------------------
--- Packets
----------------------------------------------------------------------------------

-- Ah4 packets should not be shorter than 70 bytes (cf. x540 datasheet page 308: SECP field)
pkt.getAh4Packet = packetCreate("eth", "ip4", "ah4")
-- Ah6 packets should not be shorter than 94 bytes (cf. x540 datasheet page 308: SECP field)
pkt.getAh6Packet = packetCreate("eth", "ip6", "ah6") 
pkt.getAhPacket = function(self, ip4) ip4 = ip4 == nil or ip4 if ip4 then return pkt.getAh4Packet(self) else return pkt.getAh6Packet(self) end end

------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

--ffi.metatype("union ipsec_iv", ipsecIV)
ffi.metatype("union ipsec_icv", ipsecICV)
ffi.metatype("struct ah4_header", ahHeader)
ffi.metatype("struct ah6_header", ah6Header)

return ah
