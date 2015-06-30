local ffi = require "ffi"
local pkt = require "packet"
local math = require "math"

require "headers"


---------------------------------------------------------------------------
--- esp constants 
---------------------------------------------------------------------------

local esp = {}

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
	local random_iv = ffi.new("union ipsec_iv")
	random_iv.uint32[0] = math.random(0, 2^32-1)
	random_iv.uint32[1] = math.random(0, 2^32-1)

	local iv = iv or random_iv
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

	return ("0x%08x%08x"):format(self.uint32[1], self.uint32[0])
end

---------------------------------------------------------------------------
--- esp header
---------------------------------------------------------------------------

local espHeader = {}
espHeader.__index = espHeader

--- Set the SPI.
-- @param int SPI of the esp header as A bit integer.
function espHeader:setSPI(int)
	int = int or 0
	self.spi = hton(int)
end

--- Retrieve the SPI.
-- @return SPI as A bit integer.
function espHeader:getSPI()
	return hton(self.spi)
end

--- Retrieve the SPI as string.
-- @return SPI as string.
function espHeader:getSPIString()
	return self:getSPI()
end

--- Set the SQN.
-- @param int SQN of the esp header as A bit integer.
function espHeader:setSQN(int)
	int = int or 0
	self.sqn = hton(int)
end

--- Retrieve the SQN.
-- @return SQN as A bit integer.
function espHeader:getSQN()
	return hton(self.sqn)
end

--- Retrieve the SQN as string.
-- @return SQN as string.
function espHeader:getSQNString()
	return self:getSQN()
end

--- Set the IV.
-- @param int IV of the esp header as 'union ipsec_iv'.
function espHeader:setIV(iv)
	self.iv:set(iv)
end

--- Retrieve the IV.
-- @return SPI as 'union ipsec_iv'.
function espHeader:getIV()
	return self.iv:get()
end

--- Retrieve the IV as string.
-- @return IV as string.
function espHeader:getIVString()
	return self.iv:getString(true)
end

--- Set all members of the esp header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: espSPI, espSQN
-- @param pre prefix for namedArgs. Default 'esp'.
-- @usage fill() -- only default values
-- @usage fill{ espXYZ=1 } -- all members are set to default values with the exception of espXYZ, ...
function espHeader:fill(args, pre)
	args = args or {}
	pre = pre or "esp"

	self:setSPI(args[pre .. "SPI"])
	self:setSQN(args[pre .. "SQN"])
	self:setIV(args[pre .. "IV"])
end

--- Retrieve the values of all members.
-- @param pre prefix for namedArgs. Default 'esp'.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see espHeader:fill
function espHeader:get(pre)
	pre = pre or "esp"

	local args = {}
	args[pre .. "SPI"] = self:getSPI() 
	args[pre .. "SQN"] = self:getSQN()
	args[pre .. "IV"] = self:getIV()

	return args
end

--- Retrieve the values of all members.
-- @return Values in string format.
function espHeader:getString()
	--TODO: add data from ESP trailer
	return "ESP spi " .. self:getSPIString() .. " sqn " .. self:getSQNString() .. " iv " .. self:getIVString()
end

--- Resolve which header comes after this one (in a packet)
-- For instance: in tcp/udp based on the ports
-- This function must exist and is only used when get/dump is executed on 
-- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
-- @return String next header (e.g. 'eth', 'ip4', nil)
function espHeader:resolveNextHeader()
	--TODO: next_header field is in ESP trailer
	return nil
end	

--- Change the default values for namedArguments (for fill/get)
-- This can be used to for instance calculate a length value based on the total packet length
-- See proto/ip4.setDefaultNamedArgs as an example
-- This function must exist and is only used by packet.fill
-- @param pre The prefix used for the namedArgs, e.g. 'esp'
-- @param namedArgs Table of named arguments (see See more)
-- @param nextHeader The header following after this header in a packet
-- @param accumulatedLength The so far accumulated length for previous headers in a packet
-- @see espHeader:fill
function espHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

----------------------------------------------------------------------------------
--- Packets
----------------------------------------------------------------------------------

-- Esp4 packets should not be shorter than 70 bytes (cf. x540 datasheet page 308: SECP field)
pkt.getEsp4Packet = packetCreate("eth", "ip4", "esp")
-- Esp6 packets should not be shorter than 90 bytes (cf. x540 datasheet page 308: SECP field)
pkt.getEsp6Packet = packetCreate("eth", "ip6", "esp") 
pkt.getEspPacket = function(self, ip4) ip4 = ip4 == nil or ip4 if ip4 then return pkt.getEsp4Packet(self) else return pkt.getEsp6Packet(self) end end

------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("union ipsec_iv", ipsecIV)
ffi.metatype("struct esp_header", espHeader)


return esp
