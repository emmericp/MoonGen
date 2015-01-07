local ffi = require "ffi"

require "utils"
require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bswap16
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

--- Instruct the NIC to calculate the IP and UDP checksum for this packet.
function pkt:offloadUdpChecksum(ipv4, l2_len, l3_len)
	-- NOTE: this method cannot be moved to the udpPacket class because it doesn't (and can't) know the pktbuf it belongs to
	ipv4 = ipv4 == nil or ipv4
	l2_len = l2_len or 14
	if ipv4 then
		l3_len = l3_len or 20
		self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_IPV4_CSUM, dpdk.PKT_TX_UDP_CKSUM)
		self.pkt.header_lengths = l2_len * 512 + l3_len
		-- calculate pseudo header checksum because the NIC doesn't do this...
		dpdkc.calc_ipv4_pseudo_header_checksum(self.pkt.data)
	else 
		l3_len = l3_len or 40
		self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_UDP_CKSUM)
		self.pkt.header_lengths = l2_len * 512 + l3_len
		-- calculate pseudo header checksum because the NIC doesn't do this...
		dpdkc.calc_ipv6_pseudo_header_checksum(self.pkt.data)
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


--- Layer 2 header
local etherHeader = {}
etherHeader.__index = etherHeader

function etherHeader:setDst(addr)
	for i = 0, 5 do
		self.dst.uint8[i] = addr.uint8[i]
	end
end

function etherHeader:setSrc(addr)
	for i = 0, 5 do
		self.src.uint8[i] = addr.uint8[i]
	end
end

function etherHeader:setDstString(str)
	-- TODO
end

function etherHeader:setSrcString(str)
	-- TODO
end

function etherHeader:fill()
	self:setSrcString("90:e2:ba:2c:cb:02")
	self:setDstString("90:e2:ba:35:b5:81")
	self:setType()
end

--- Layer 2 packet
local etherPacketType = ffi.typeof("struct ethernet_packet*")
local etherPacket = {}
etherPacket.__index = etherPacket

function pkt:getEthernetPacket()
	return etherPacketType(self.pkt.data)
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

-- TODO adjust default values

-- @param int ip header version, should always be '4' 
--		  4 bit integer
function ip4Header:setVersion(int)
	int = int or 4
	int = band(lshift(int, 4), 0xf0) -- fill to 8 bits
	
	old = self.verihl
	old = band(old, 0x0f) -- remove old value
	
	self.verihl = bor(old, int)
end

-- @param int length of the ip header (in multiple of 32 bits)
--		  4 bit integer
function ip4Header:setHeaderLength(int)
	int = int or 5
	int = band(int, 0x0f)	
	
	old = self.verihl
	old = band(old, 0xf0)
	
	self.verihl = bor(old, int)
end

function ip4Header:setTOS(int)
	int = int or 0 
	self.tos = int
end

function ip4Header:setLength(int)
	int = int or 48	-- with eth + UDP -> minimum 64
	self.len = hton16(int)
end

function ip4Header:setID(int)
	int = int or 0 
	self.id = hton16(int)
end

function ip4Header:setFragment(int)
	int = int or 0 
	self.frag = hton16(int)
end

function ip4Header:setTTL(int)
	int = int or 64 
	self.ttl = int
end

function ip4Header:setProtocol(int)
	int = int or 0x11 	-- UDP
	self.protocol = int
end

function ip4Header:setChecksum(int)
	int = int or 0
	self.cs = int
end

--- Calculate and set the IPv4 header checksum
-- If possible use checksum offloading (see pkt:offloadUdpChecksum) instead
function ip4Header:calculateChecksum()
	self:setChecksum() -- just to be sure (packet may be reused); must be 0 
	self:setChecksum(checksum(self, 20))
end

function ip4Header:setDst(int)
	self.dst:set(int)
end

function ip4Header:setSrc(int)
	self.src:set(int)
end

function ip4Header:setDstString(str)
	self:setDst(parseIP4Address(str))
end

function ip4Header:setSrcString(str)
	self:setSrc(parseIP4Address(str))
end

function ip4Header:fill()
	self:setVersion()
	self:setHeaderLength()
	self:setTOS()
	self:setLength()
	self:setID()
	self:setFragment()
	self:setTTL()
	self:setProtocol()
	self:setChecksum()
	self:setSrcString("192.168.1.1")
	self:setDstString("192.168.1.2")
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

--- Add a number to an IPv4 address in-place, max 32 bit
-- @param val number to add
function ip4Addr:add(val)
	self.uint32 = self.uint32 + val
end

--- Subtract a number from an IPv4 address
-- max. 32 bit
-- @param val number to substract
-- @return resulting address in uint32 format
function ip4Addr:__sub(val)
	return self + -val
end

--- ipv6 packets
local udp6PacketType = ffi.typeof("struct udp_v6_packet*")

--- Retrieve an IPv6 UDP packet
-- @return the packet in udp_v6_packet format
function pkt:getUDP6Packet()
	return udp6PacketType(self.pkt.data)
end

local ip6Header = {}
ip6Header.__index = ip6Header

-- TODO adjust default values

-- @param int ip header version, should always be '6' 
--		  4 bit integer
function ip6Header:setVersion(int)
	int = int or 6
	int = band(lshift(int, 28), 0xf0000000) -- fill to 32 bits
	
	old = bswap(self.vtf)
	old = band(old, 0x0fffffff)	-- remove old value
	
	self.vtf = bswap(bor(old, int))
end

-- @param int ip set traffic class of the ip header
--		  8 bit integer
function ip6Header:setTrafficClass(int)
	int = int or 0
	int = band(lshift(int, 20), 0x0ff00000)
	
	old = bswap(self.vtf)
	old = band(old, 0xf00fffff)
	
	self.vtf = bswap(bor(old, int))
end

-- @param int ip set flow label of the ip header
--		  20 bit integer
function ip6Header:setFlowLabel(int)
	int = int or 0
	int = band(int, 0x000fffff)
	
	old = bswap(self.vtf)
	old = band(old, 0xfff00000)
	
	self.vtf = bswap(bor(old, int))
end

function ip6Header:setLength(int)
	int = int or 8	-- with eth + UDP -> minimum 64
	self.len = hton16(int)
end

function ip6Header:setNextHeader(int)
	int = int or 0x11	-- UDP
	self.nextHeader = int
end

function ip6Header:setTTL(int)
	int = int or 64
	self.ttl = int
end

function ip6Header:setDst(addr)
	self.dst:set(addr)
end

function ip6Header:setSrc(addr)
	self.src:set(addr)
end

function ip6Header:setDstString(str)
	self:setDst(parseIP6Address(str))
end

function ip6Header:setSrcString(str)
	self:setSrc(parseIP6Address(str))
end

function ip6Header:fill()
	self:setVersion()
	self:setTrafficClass()
	self:setFlowLabel()
	self:setLength()
	self:setNextHeader()
	self:setTTL()
	self:setSrcString("fe80::1")
	self:setDstString("fe80::2")
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
	local addr = ip6AddrType()
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

--- Add a number to an IPv6 address in-place, max 64 bit
-- @param val number to add
function ip6Addr:add(val)
	-- calc ip (self) + number (val)
	local low, high = bswap(self.uint64[1]), bswap(self.uint64[0])
	low = low + val
	-- handle overflow
	if low < val and val > 0 then
		high = high + 1
	-- handle underflow
	elseif low > -val and val < 0 then
		high = high - 1
	end
	self.uint64[1] = bswap(low)
	self.uint64[0] = bswap(high)
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

-- udp packets

local udpPacket = {}
udpPacket.__index = udpPacket

function udpPacket_fill()
	self.eth:fill()
	self.ip:fill()
	--self.udp:fill()
end

--- Calculate and set the UDP header checksum for IPv4 packets
function udpPacket:calculateUDPChecksum()
    -- optional, so don't do it
	self.udp.cs = 0
end

local udp6Packet = {}
udp6Packet.__index = udp6Packet

function udp6Packet:fill()
	self.eth:fill()
	self.ip:fill()
	--self.udp:fill()
end

--- Calculate and set the UDP header checksum for IPv6 packets
function udp6Packet:calculateUDPChecksum()
	-- TODO as it is mandatory for IPv6 UDP packets
	self.udp.cs = 0
end

ffi.metatype("struct mac_address", macAddr)
ffi.metatype("struct ethernet_packet", etherPacket)
ffi.metatype("struct ethernet_header", etherHeader)

ffi.metatype("struct ipv4_header", ip4Header)
ffi.metatype("struct ipv6_header", ip6Header)
ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("union ipv6_address", ip6Addr)

--ffi.metatype("struct udp_header", udpHeader)

ffi.metatype("struct udp_packet", udpPacket)
ffi.metatype("struct udp_v6_packet", udp6Packet)

ffi.metatype("struct rte_mbuf", pkt)

