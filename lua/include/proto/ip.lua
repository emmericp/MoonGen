local ffi = require "ffi"

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

ip.PROTO_TCP = 0x06
ip.PROTO_UDP = 0x11


----------------------------------------------------------------------------------
--- IPv4 addresses
----------------------------------------------------------------------------------

local ip4Addr = {}
ip4Addr.__index = ip4Addr
local ip4AddrType = ffi.typeof("union ipv4_address")

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
-- @param lhs Address in 'union ipv4_address' format.
-- @param rhs Address in 'union ipv4_address' format.
-- @return true if equal, false otherwise.
function ip4Addr.__eq(lhs, rhs)
	return istype(ip4AddrType, lhs) and istype(ip4AddrType, rhs) and lhs.uint32 == rhs.uint32
end 

--- Add a number to an IPv4 address.
-- Max. 32 bit, commutative.
-- @param lhs Address in 'union ipv4_address' format.
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
	
	if proto == ip.PROTO_UDP then
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
-- @param int Address in 'union ipv4_address' format.
function ip4Header:setDst(int)
	self.dst:set(int)
end

--- Retrieve the destination IP address. 
-- @return Address in 'union ipv4_address' format.
function ip4Header:getDst()
	return self.dst:get()
end

--- Set the source address.
-- @param int Address in 'union ipv4_address' format.
function ip4Header:setSrc(int)
	self.src:set(int)
end

--- Retrieve the source IP address. 
-- @return Address in 'union ipv4_address' format.
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
-- @usage fill() -- only default values
-- @usage fill{ ipSrc="1.1.1.1", ipTTL=100 } -- all members are set to default values with the exception of ipSrc and ipTTL
function ip4Header:fill(args)
	args = args or {}

	self:setVersion(args.ipVersion)
	self:setHeaderLength(args.ipHeaderLength)
	self:setTOS(args.ipTOS)
	self:setLength(args.ipLength)
	self:setID(args.ipID)
	self:setFlags(args.ipFlags)
	self:setFragment(args.ipFragment)
	self:setTTL(args.ipTTL)
	self:setProtocol(args.ipProtocol)
	self:setChecksum(args.ipChecksum)

	args.ipSrc = args.ipSrc or "192.168.1.1"
	args.ipDst = args.ipDst or "192.168.1.2"
	
	-- if for some reason the address is in 'union ipv4_address' format, cope with it
	if type(args.ipSrc) == "string" then
		self:setSrcString(args.ipSrc)
	else
		self:setSrc(args.ipSrc)
	end
	if type(args.ipDst) == "string" then
		self:setDstString(args.ipDst)
	else
		self:setDst(args.ipDst)
	end
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see ip4Header:fill
function ip4Header:get()
	return { ipSrc=self:getSrcString(), ipDst=self:getDstString(), ipVersion=self:getVersion(), ipHeaderLength=self:getHeaderLength(), ipTOS=self:getTOS(), ipLength=self:getLength(), 
			 ipID=self:getID(), ipFlags=self:getFlags(), ipFragment=self:getFragment(), ipTTL=self:getTTL(), ipProtocol=self:getProtocol(), ipChecksum=self:getChecksum() }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function ip4Header:getString()
	return "IP4 " .. self:getSrcString() .. " > " .. self:getDstString() .. " ver " .. self:getVersionString() 
		   .. " ihl " .. self:getHeaderLengthString() .. " tos " .. self:getTOSString() .. " len " .. self:getLengthString()
		   .. " id " .. self:getIDString() .. " flags " .. self:getFlagsString() .. " frag " .. self:getFragmentString() 
		   .. " ttl " .. self:getTTLString() .. " proto " .. self:getProtocolString() .. " cksum " .. self:getChecksumString() .. " "
end


-------------------------------------------------------------------------------------------
--- IPv4 packets
-------------------------------------------------------------------------------------------

local ip4Packet = {}
ip4Packet.__index = ip4Packet

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set the length member of the ip header.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ipTTL=100 } -- all members are set to default values with the exception of ethSrc and ipTTL
-- @usage fill{ pktLength=64 } -- only default values, ipLength is set to the respective value
-- @see etherHeader:fill
-- @see ip4Header:fill
function ip4Packet:fill(args)
	args = args or {}
	
	-- calculate length value for ip headers
	if args.pktLength then
		args.ipLength = args.pktLength - 14 -- ethernet
	end

	self.eth:fill(args)
	self.ip:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip4Header:get
function ip4Packet:get()
	return mergeTables(self.eth:get(), self.ip:get())
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function ip4Packet:dump(bytes)
	str = getTimeMicros() .. self.eth:getString() .. self.ip:getString()
	printLength(str, 60)
	dumpHex(self, bytes)
end


------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("struct ipv4_header", ip4Header)
ffi.metatype("struct ip_packet", ip4Packet)

return ip
