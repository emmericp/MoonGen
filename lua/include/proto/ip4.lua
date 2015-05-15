local ffi = require "ffi"
local pkt = require "packet"

require "utils"
require "headers"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format

----------------------------------------------------------------------------------
--- IPv4 constants
----------------------------------------------------------------------------------

local ip = {}

ip.PROTO_ICMP	= 0x01
ip.PROTO_TCP	= 0x06
ip.PROTO_UDP	= 0x11


----------------------------------------------------------------------------------
--- IPv4 addresses
----------------------------------------------------------------------------------

local ip4Addr = {}
ip4Addr.__index = ip4Addr
local ip4AddrType = ffi.typeof("union ip4_address")

--- Retrieve the IPv4 address.
-- @return Address in uint32 format.
function ip4Addr:get()
	return bswap(self.uint32)
end

--- Set the IPv4 address.
-- @param ip Address in uint32 format.
function ip4Addr:set(ip)
	self.uint32 = bswap(ip)
end

--- Set the IPv4 address.
-- @param ip Address in string format.
function ip4Addr:setString(ip)
	self:set(parseIPAddress(ip))
end

--- Retrieve the string representation of the IPv4 address.
-- @return Address in string format.
function ip4Addr:getString()
	return ("%d.%d.%d.%d"):format(self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3])
end


--- Test equality of two IPv4 addresses.
-- @param lhs Address in 'union ip4_address' format.
-- @param rhs Address in 'union ip4_address' format.
-- @return true if equal, false otherwise.
function ip4Addr.__eq(lhs, rhs)
	return istype(ip4AddrType, lhs) and istype(ip4AddrType, rhs) and lhs.uint32 == rhs.uint32
end 

--- Add a number to an IPv4 address.
-- Max. 32 bit, commutative.
-- @param lhs Address in 'union ip4_address' format.
-- @param rhs Number to add (32 bit integer).
-- @return Resulting address in uint32 format.
function ip4Addr.__add(lhs, rhs)
	-- calc ip (self) + number (val)
	local self, val
	if istype(ip4AddrType, lhs) then
		self = lhs
		val = rhs
	else
		-- commutative for number + ip
		self = rhs
		val = lhs
	end -- TODO: ip + ip?

	return self:get() + val
end

--- Add a number to an IPv4 address in-place.
-- Max. 32 bit.
-- @param val Number to add (32 bit integer).
function ip4Addr:add(val)
	self:set(self:get() + val)
end

--- Subtract a number from an IPv4 address.
-- Max. 32 bit.
-- @param val Number to substract (32 bit integer)
-- @return Resulting address in uint32 format.
function ip4Addr:__sub(val)
	return self + -val
end


-----------------------------------------------------------------------------------
-- IPv4 header
-----------------------------------------------------------------------------------

local ip4Header = {}

ip4Header.__index = ip4Header

--- Set the version.
-- @param int IP header version as 4 bit integer. Should always be '4'.
function ip4Header:setVersion(int)
	int = int or 4
	int = band(lshift(int, 4), 0xf0) -- fill to 8 bits
	
	old = self.verihl
	old = band(old, 0x0f) -- remove old value
	
	self.verihl = bor(old, int)
end

--- Retrieve the version.
-- @return Version as 4 bit integer.
function ip4Header:getVersion()
	return band(rshift(self.verihl, 4), 0x0f)
end

--- Retrieve the version.
-- @return Version as string.
function ip4Header:getVersionString()
	return self:getVersion()
end

--- Set the header length.
-- @param int Length of the ip header (in multiple of 32 bits) as 4 bit integer. Should always be '5'.
function ip4Header:setHeaderLength(int)
	int = int or 5
	int = band(int, 0x0f)	
	
	old = self.verihl
	old = band(old, 0xf0)
	
	self.verihl = bor(old, int)
end

--- Retrieve the header length.
-- @return Header length as 4 bit integer.
function ip4Header:getHeaderLength()
	return band(self.verihl, 0x0f)
end

--- Retrieve the header length.
-- @return Header length as string.
function ip4Header:getHeaderLengthString()
	return self:getHeaderLength()
end

--- Set the type of service (TOS).
-- @param int TOS of the ip header as 8 bit integer.
function ip4Header:setTOS(int)
	int = int or 0 
	self.tos = int
end

--- Retrieve the type of service.
-- @return TOS as 8 bit integer.
function ip4Header:getTOS()
	return self.tos
end

--- Retrieve the type of service.
-- @return TOS as string.
function ip4Header:getTOSString()
	return self:getTOS()
end

--- Set the total length.
-- @param int Length of the packet excluding layer 2. 16 bit integer.
function ip4Header:setLength(int)
	int = int or 48	-- with eth + UDP -> minimum 64
	self.len = hton16(int)
end

--- Retrieve the length.
-- @return Length as 16 bit integer.
function ip4Header:getLength()
	return hton16(self.len)
end

--- Retrieve the length.
-- @return Length as string.
function ip4Header:getLengthString()
	return self:getLength()
end

--- Set the identification.
-- @param int ID of the ip header as 16 bit integer.
function ip4Header:setID(int)
	int = int or 0 
	self.id = hton16(int)
end

--- Retrieve the identification.
-- @return ID as 16 bit integer.
function ip4Header:getID()
	return hton16(self.id)
end

--- Retrieve the identification.
-- @return ID as string.
function ip4Header:getIDString()
	return self:getID()
end

--- Set the flags.
-- Bits: [ reserved (must be 0) | don't fragment | more fragments ]
-- @param int Flags of the ip header as 3 bit integer
function ip4Header:setFlags(int)
	int = int or 0
	int = band(lshift(int, 13), 0xe000) -- fill to 16 bits
	
	old = hton16(self.frag)
	old = band(old, 0x1fff) -- remove old value
	
	self.frag = hton16(bor(old, int))
end

--- Retrieve the flags. 
-- @return Flags as 3 bit integer.
function ip4Header:getFlags()
	return band(rshift(hton16(self.frag), 13), 0x000e)
end

--- Retrieve the flags. 
-- @return Flags as string.
function ip4Header:getFlagsString()
	flags = self:getFlags()
	--TODO show flags in a more clever manner: 1|1|1 or reserved|DF|MF
	return flags
end

--- Set the fragment.
-- @param int Fragment of the ip header as 13 bit integer.
function ip4Header:setFragment(int)
	int = int or 0 
	int = band(int, 0x1fff)

	old = hton16(self.frag)
	old = band(old, 0xe000)
	
	self.frag = hton16(bor(old, int))
end

--- Retrieve the fragment. 
-- @return Fragment as 13 bit integer.
function ip4Header:getFragment()
	return band(hton16(self.frag), 0x1fff)
end

--- Retrieve the fragemt. 
-- @return Fragment as string.
function ip4Header:getFragmentString()
	return self:getFragment()
end

--- Set the time-to-live (TTL).
-- @param int TTL of the ip header as 8 bit integer.
function ip4Header:setTTL(int)
	int = int or 64 
	self.ttl = int
end

--- Retrieve the time-to-live. 
-- @return TTL as 8 bit integer.
function ip4Header:getTTL()
	return self.ttl
end

--- Retrieve the time-to-live. 
-- @return TTL as string.
function ip4Header:getTTLString()
	return self:getTTL()
end

--- Set the next layer protocol.
-- @param int Next layer protocol of the ip header as 8 bit integer.
function ip4Header:setProtocol(int)
	int = int or ip.PROTO_UDP
	self.protocol = int
end

--- Retrieve the next layer protocol. 
-- @return Next layer protocol as 8 bit integer.
function ip4Header:getProtocol()
	return self.protocol
end

--- Retrieve the next layer protocol. 
-- @return Next layer protocol as string.
function ip4Header:getProtocolString()
	local proto = self:getProtocol()
	local cleartext = ""
	
	if proto == ip.PROTO_ICMP then
		cleartext = "(ICMP)"
	elseif proto == ip.PROTO_UDP then
		cleartext = "(UDP)"
	elseif proto == ip.PROTO_TCP then
		cleartext = "(TCP)"
	else
		cleartext = "(unknown)"
	end
	
	return format("0x%02x %s", proto, cleartext)
end

--- Set the checksum.
-- @param int Checksum of the ip header as 16 bit integer.
-- @see ip4Header:calculateChecksum
-- @see pkt:offloadUdpChecksum
function ip4Header:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Retrieve the checksum. 
-- @return Checksum as 16 bit integer.
function ip4Header:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum. 
-- @return Checksum as string.
function ip4Header:getChecksumString()
	return format("0x%04x", self:getChecksum())
end

--- Calculate and set the checksum.
-- If possible use checksum offloading instead.
-- @see pkt:offloadUdpChecksum
function ip4Header:calculateChecksum()
	self:setChecksum() -- just to be sure (packet may be reused); must be 0 
    self:setChecksum(hton16(checksum(self, 20)))
end

--- Set the destination address.
-- @param int Address in 'union ip4_address' format.
function ip4Header:setDst(int)
	self.dst:set(int)
end

--- Retrieve the destination IP address. 
-- @return Address in 'union ip4_address' format.
function ip4Header:getDst()
	return self.dst:get()
end

--- Set the source address.
-- @param int Address in 'union ip4_address' format.
function ip4Header:setSrc(int)
	self.src:set(int)
end

--- Retrieve the source IP address. 
-- @return Address in 'union ip4_address' format.
function ip4Header:getSrc()
	return self.src:get()
end

--- Set the destination address.
-- @param str Address in string format.
function ip4Header:setDstString(str)
	self.dst:setString(str)
end

--- Retrieve the destination IP address. 
-- @return Address in string format.
function ip4Header:getDstString()
	return self.dst:getString()
end

--- Set the source address.
-- @param str Address in string format.
function ip4Header:setSrcString(str)
	self.src:setString(str)
end

--- Retrieve the source IP address. 
-- @return Address in string format.
function ip4Header:getSrcString()
	return self.src:getString()
end

--- Set all members of the ip header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ipVersion, ipHeaderLength, ipTOS, ipLength, ipID, ipFlags, ipFragment, ipTTL, ipProtocol, ipChecksum, ipSrc, ipDst
-- @param pre prefix for namedArgs. Default 'ip4'.
-- @usage fill() -- only default values
-- @usage fill{ ipSrc="1.1.1.1", ipTTL=100 } -- all members are set to default values with the exception of ipSrc and ipTTL
function ip4Header:fill(args, pre)
	args = args or {}
	pre = pre or "ip4"
	
	self:setVersion(args[pre .. "Version"])
	self:setHeaderLength(args[pre .. "HeaderLength"])
	self:setTOS(args[pre .. "TOS"])
	self:setLength(args[pre .. "Length"])
	self:setID(args[pre .. "ID"])
	self:setFlags(args[pre .. "Flags"])
	self:setFragment(args[pre .. "Fragment"])
	self:setTTL(args[pre .. "TTL"])
	self:setProtocol(args[pre .. "Protocol"])
	self:setChecksum(args[pre .. "Checksum"])

	local src = pre .. "Src"
	local dst = pre .. "Dst"
	args[src] = args[src] or "192.168.1.1"
	args[dst] = args[dst] or "192.168.1.2"
	
	-- if for some reason the address is in 'union ip4_address' format, cope with it
	if type(args[src]) == "string" then
		self:setSrcString(args[src])
	else
		self:setSrc(args[src])
	end
	if type(args[dst]) == "string" then
		self:setDstString(args[dst])
	else
		self:setDst(args[dst])
	end
end

--- Retrieve the values of all members.
-- @param pre prefix for namedArgs. Default 'ip4'.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see ip4Header:fill
function ip4Header:get(pre)
	pre = pre or "ip4"

	local args = {}
	args[pre .. "Src"] = self:getSrcString()
	args[pre .. "Dst"] = self:getDstString()
	args[pre .. "Version"] = self:getVersion()
	args[pre .. "HeaderLength"] = self:getHeaderLength()
	args[pre .. "TOS"] = self:getTOS()
	args[pre .. "Length"] = self:getLength()
	args[pre .. "ID"] = self:getID()
	args[pre .. "Flags"] = self:getFlags()
	args[pre .. "Fragment"] = self:getFragment()
	args[pre .. "TTL"] = self:getTTL()
	args[pre .. "Protocol"] = self:getProtocol()
	args[pre .. "Checksum"] = self:getChecksum()

	return args	
end

--- Retrieve the values of all members.
-- @return Values in string format.
function ip4Header:getString()
	return "IP4 " .. self:getSrcString() .. " > " .. self:getDstString() .. " ver " .. self:getVersionString() 
		   .. " ihl " .. self:getHeaderLengthString() .. " tos " .. self:getTOSString() .. " len " .. self:getLengthString()
		   .. " id " .. self:getIDString() .. " flags " .. self:getFlagsString() .. " frag " .. self:getFragmentString() 
		   .. " ttl " .. self:getTTLString() .. " proto " .. self:getProtocolString() .. " cksum " .. self:getChecksumString()
end

local mapNameProto = {
	icmp = ip.PROTO_ICMP,
	udp = ip.PROTO_UDP,
	tcp = ip.PROTO_TCP,
}

function ip4Header:resolveNextHeader()
	local proto = self:getProtocol()
	for name, _proto in pairs(mapNameProto) do
		if proto == _proto then
			return name
		end
	end
	return nil
end

function ip4Header:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	-- set length
	if not namedArgs[pre .. "Length"] and namedArgs["pktLength"] then
		namedArgs[pre .. "Length"] = namedArgs["pktLength"] - accumulatedLength
	end
	
	-- set protocol
	if not namedArgs[pre .. "Protocol"] then
		for name, type in pairs(mapNameProto) do
			if nextHeader == name then
				namedArgs[pre .. "Protocol"] = type
				break
			end
		end
	end
	return namedArgs
end


----------------------------------------------------------------------------------
--- Packets
----------------------------------------------------------------------------------

pkt.getIP4Packet = packetCreate("eth", "ip4") 
pkt.getIPPacket = function(self, ip4) ip4 = ip4 == nil or ip4 if ip4 then return pkt.getIP4Packet(self) else return pkt.getIP6Packet(self) end end   


pkt.getTestPacket = packetCreate("ip4", {"ip4", "innerIp4"}, {"ip4", "deepIp4"})

------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("union ip4_address", ip4Addr)
ffi.metatype("struct ip4_header", ip4Header)

return ip
