local ffi = require "ffi"

require "utils"
require "headers"
require "dpdkc"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bwswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype

local pkt = {}
pkt.__index = pkt

--- Retrieve the time stamp information
-- @return the timestamp or nil if the packet was not time stamped
function pkt:getTimestamp()
	if bit.bor(self.ol_flags, dpdk.PKT_RX_IEEE1588_TMST) ~= 0 then
		-- TODO: support timestamps that are stored in registers instead of the rx buffer
		local data = ffi.cast("uint32_t* ", self.pkt.data)
		-- TODO: this is only tested with the Intel 82580 NIC at the moment
		-- the datasheet claims that low and high are swapped, but this doesn't seem to be the case
		-- TODO: check other NICs
		local low = data[2]
		local high = data[3]
		return high * 2^32 + low
	end
end

local macAddr = {}
macAddr.__index = macAddr
local macAddrType = ffi.typeof("struct mac_address")

--- Retrieve the MAC address
-- @return address in mac_address format
function macAddr:get()
	local addr = macAddrType()
	for i = 0, 5 do
		addr.uint8[i] = self.uint8[i]
	end
	return addr
end

--- Set the MAC address
-- @param addr address in mac_address format
function macAddr:set(addr)
	for i = 0, 5 do
		self.uint8[i] = addr.uint8[i]
	end
end

--- Set the MAC address
-- @param mac address in string format
function macAddr:setString(mac)
	self:set(parseMACAddress(mac))
end

--- Test equality of two MAC addresses
-- @param lhs address in mac_address format
-- @param rhs address in mac_address format
-- @return is equal
function macAddr.__eq(lhs, rhs)
	local isMAC = istype(macAddrType, lhs) and istype(macAddrType, rhs) 
	for i = 0, 5 do
		isMAC = isMAC and lhs.uint8[i] == rhs.uint8[i] 
	end
	return isMAC
end

-- Retrieve the string representation of an MAC address
-- @return address in string format
function macAddr:getString()
	return ("%02x:%02x:%02x:%02x:%02x:%02x"):format(
			self.uint8[0], self.uint8[1], self.uint8[2], 
			self.uint8[3], self.uint8[4], self.uint8[5]
			)
end

---ip packets
local udpPacketType = ffi.typeof("struct udp_packet*")

--- Retrieve an IPv4 UDP packet
-- @return the packet in udp_packet format
function pkt:getUDPPacket()
	return udpPacketType(self.pkt.data)
end

local ip4Header = {}
ip4Header.__index = ip4Header

--- Calculate and set the IPv4 header checksum
function ip4Header:calculateChecksum()
	self.cs = 0 --just to be sure...
	self.cs = checksum(self, 20)
end

local ip4Addr = {}
ip4Addr.__index = ip4Addr
local ip4AddrType = ffi.typeof("union ipv4_address")

--- Retrieve the IPv4 address
-- @return address in uint32 format
function ip4Addr:get()
	return bswap(self.uint32)
end

--- Set the IPv4 address
-- @param ip address in uint32 format
function ip4Addr:set(ip)
	self.uint32 = bswap(ip)
end

--- Set the IPv4 address
-- @param ip address in string format
function ip4Addr:setString(ip)
	self:set(parseIPAddress(ip))
end

-- Retrieve the string representation of an IPv4 address
-- @return address in string format
function ip4Addr:getString()
	return ("%d.%d.%d.%d"):format(self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3])
end

local udpPacket = {}
udpPacket.__index = udpPacket

--- Test equality of two IPv4 addresses
-- @param lhs address in ipv4_address format
-- @param rhs address in ipv4_address format
-- @return is equal
function ip4Addr.__eq(lhs, rhs)
	return istype(ip4AddrType, lhs) and istype(ip4AddrType, rhs) and lhs.uint32 == rhs.uint32
end 

--- Add a number to an IPv4 address
-- max. 32 bit, commutative
-- @param lhs address in ipv4_address format
-- @param rhs number to add
-- @return resulting address in uint32 format
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

	return self.uint32 + val
end

--- Subtract a number from an IPv4 address
-- max. 32 bit
-- @param val number to substract
-- @return resulting address in uint32 format
function ip4Addr:__sub(val)
	return self + -val
end

--- Calculate and set the UDP header checksum for IPv4 packets
function udpPacket:calculateUDPChecksum()
	-- optional, so don't do it
	self.udp.cs = 0
end

--- ipv6 packets
local udp6PacketType = ffi.typeof("struct udp_v6_packet*")

--- Retrieve an IPv6 UDP packet
-- @return the packet in udp_v6_packet format
function pkt:getUDP6Packet()
	return udp6PacketType(self.pkt.data)
end

local ip6Addr = {}
ip6Addr.__index = ip6Addr
local ip6AddrType = ffi.typeof("union ipv6_address")

--- Retrieve the IPv6 address
-- @return address in ipv6_address format
function ip6Addr:get()
	local addr = ip6AddrType()
	addr.uint32[0] = bswap(self.uint32[3])
	addr.uint32[1] = bswap(self.uint32[2])
	addr.uint32[2] = bswap(self.uint32[1])
	addr.uint32[3] = bswap(self.uint32[0])
	return addr
end

--- Set the IPv6 address
-- @param addr address in ipv6_address format
function ip6Addr:set(addr)
	self.uint32[0] = bswap(addr.uint32[3])
	self.uint32[1] = bswap(addr.uint32[2])
	self.uint32[2] = bswap(addr.uint32[1])
	self.uint32[3] = bswap(addr.uint32[0])
end

--- Set the IPv6 address
-- @param ip address in string format
function ip6Addr:setString(ip)
	self:set(parseIP6Address(ip))
end

--- Test equality of two IPv6 addresses
-- @param lhs address in ipv6_address format
-- @param rhs address in ipv6_address format
-- @return is equal
function ip6Addr.__eq(lhs, rhs)
	return istype(ip6AddrType, lhs) and istype(ip6AddrType, rhs) and lhs.uint64[0] == rhs.uint64[0] and lhs.uint64[1] == rhs.uint64[1]
end

--- Add a number to an IPv6 address
-- max. 64bit, commutative
-- @param lhs address in ipv6_address format
-- @param rhs number to add
-- @return resulting address in ipv6_address format
function ip6Addr.__add(lhs, rhs)
	-- calc ip (self) + number (val)
	local self, val
	if istype(ip6AddrType, lhs) then
		self = lhs
		val = rhs
	else
		-- commutative for number + ip
		self = rhs
		val = lhs
	end -- TODO: ip + ip?
	local addr = ffi.new("union ipv6_address")
	local low, high = self.uint64[0], self.uint64[1]
	low = low + val
	-- handle overflow
	if low < val and val > 0 then
		high = high + 1
	-- handle underflow
	elseif low > -val and val < 0 then
		high = high - 1
	end
	addr.uint64[0] = low
	addr.uint64[1] = high
	return addr
end

--- Subtract a number from an IPv6 address
-- max. 64 bit
-- @param val number to substract
-- @return resulting address in ipv6_address format
function ip6Addr:__sub(val)
	return self + -val
end

-- Retrieve the string representation of an IPv6 address.
-- Assumes ipv6_address is in network byteorder
-- @param doByteSwap change byteorder
-- @return address in string format
function ip6Addr:getString(doByteSwap)
	doByteSwap = doByteSwap or false
	if doByteSwap then
		self = self:get()
	end

	return ("%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x"):format(
			self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3], 
			self.uint8[4], self.uint8[5], self.uint8[6], self.uint8[7], 
			self.uint8[8], self.uint8[9], self.uint8[10], self.uint8[11], 
			self.uint8[12], self.uint8[13], self.uint8[14], self.uint8[15]
			)
end

-- udp
local udp6Packet = {}
udp6Packet.__index = udp6Packet

--- Calculate and set the UDP header checksum for IPv6 packets
function udp6Packet:calculateUDPChecksum()
	-- TODO as it is mandatory for IPv6 UDP packets
	self.udp.cs = 0
end

ffi.metatype("struct mac_address", macAddr)
ffi.metatype("struct ipv4_header", ip4Header)
ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("union ipv6_address", ip6Addr)
ffi.metatype("struct udp_packet", udpPacket)
ffi.metatype("struct udp_v6_packet", udp6Packet)
ffi.metatype("struct rte_mbuf", pkt)


