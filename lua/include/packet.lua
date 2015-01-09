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

--- Retrieve the time stamp information.
-- @return The timestamp or nil if the packet was not time stamped.
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
-- @param ipv4 Boolean to decide whether the packet uses IPv4 (set to nil/true) or IPv6 (set to anything else).
-- @param l2_len Length of the layer 2 header in bytes (default 14 bytes for ethernet).
-- @param l3_len Length of the layer 3 header in bytes (default 20 bytes for IPv4, 40 bytes for IPv6).
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

--- Retrieve the MAC address.
-- @return Address in 'struct mac_address' format.
function macAddr:get()
	local addr = macAddrType()
	for i = 0, 5 do
		addr.uint8[i] = self.uint8[i]
	end
	return addr
end

--- Set the MAC address.
-- @param addr Address in 'struct mac_address' format.
function macAddr:set(addr)
	for i = 0, 5 do
		self.uint8[i] = addr.uint8[i]
	end
end

--- Set the MAC address.
-- @param mac Address in string format.
function macAddr:setString(mac)
	self:set(parseMACAddress(mac))
end

--- Test equality of two MAC addresses.
-- @param lhs Address in 'struct mac_address' format.
-- @param rhs Address in 'struct mac_address' format.
-- @return true if equal, false otherwise.
function macAddr.__eq(lhs, rhs)
	local isMAC = istype(macAddrType, lhs) and istype(macAddrType, rhs) 
	for i = 0, 5 do
		isMAC = isMAC and lhs.uint8[i] == rhs.uint8[i] 
	end
	return isMAC
end

--- Retrieve the string representation of a MAC address.
-- @return Address in string format.
function macAddr:getString()
	return ("%02x:%02x:%02x:%02x:%02x:%02x"):format(
			self.uint8[0], self.uint8[1], self.uint8[2], 
			self.uint8[3], self.uint8[4], self.uint8[5]
			)
end


--- Layer 2 header
local etherHeader = {}
etherHeader.__index = etherHeader

--- Set the destination MAC address.
-- @param addr Address in 'struct mac_address' format.
function etherHeader:setDst(addr)
	self.dst:set(addr)
end

--- Set the source MAC address.
-- @param addr Address in 'struct mac_address' format.
function etherHeader:setSrc(addr)
	self.src:set(addr)
end

--- Set the destination MAC address.
-- @param str Address in string format.
function etherHeader:setDstString(str)
	self:setDst(parseMACAddress(str))
end

--- Set the source MAC address.
-- @param str Address in string format.
function etherHeader:setSrcString(str)
	self:setSrc(parseMACAddress(str))
end

--- Set the EtherType.
-- @param int EtherType as 16 bit integer.
function etherHeader:setType(int)
	int = int or 0x0800 -- ipv4
	self.type = hton16(int)
end

--- Set all members of the ethernet header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ethSrc, ethDst, ethType
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ethType=0x137 } -- default value for ethDst; ethSrc and ethType user-specified
function etherHeader:fill(args)
	self:setSrcString(args.ethSrc or "01:02:03:04:05:06")
	self:setDstString(args.ethDst or "07:08:09:0a:0b:0c")
	self:setType(args.ethType)
end

--- Layer 2 packet
local etherPacketType = ffi.typeof("struct ethernet_packet*")
local etherPacket = {}
etherPacket.__index = etherPacket

--- Retrieve an ethernet packet.
-- @return Packet in 'struct ethernet_packet' format
function pkt:getEthernetPacket()
	return etherPacketType(self.pkt.data)
end


---ip packets
local udpPacketType = ffi.typeof("struct udp_packet*")

--- Retrieve an IPv4 UDP packet.
-- @return Packet in 'struct udp_packet' format.
function pkt:getUDPPacket()
	return udpPacketType(self.pkt.data)
end

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

--- Set the header length.
-- @param int Length of the ip header (in multiple of 32 bits) as 4 bit integer. Should always be '5'.
function ip4Header:setHeaderLength(int)
	int = int or 5
	int = band(int, 0x0f)	
	
	old = self.verihl
	old = band(old, 0xf0)
	
	self.verihl = bor(old, int)
end

--- Set the type of service (TOS).
-- @param int TOS of the ip header as 8 bit integer.
function ip4Header:setTOS(int)
	int = int or 0 
	self.tos = int
end

--- Set the total length.
-- @param int Length of the packet excluding layer 2. 16 bit integer.
function ip4Header:setLength(int)
	int = int or 48	-- with eth + UDP -> minimum 64
	self.len = hton16(int)
end

--- Set the identification.
-- @param int ID of the ip header as 16 bit integer.
function ip4Header:setID(int)
	int = int or 0 
	self.id = hton16(int)
end

-- TODO setFlags: 3 bit
-- Fragment is only 13 bit

--- Set the fragment.
-- @param int Fragment of the ip header as 16 bit integer.
function ip4Header:setFragment(int)
	int = int or 0 
	self.frag = hton16(int)
end

--- Set the time-to-live (TTL).
-- @param int TTL of the ip header as 8 bit integer.
function ip4Header:setTTL(int)
	int = int or 64 
	self.ttl = int
end

--- Set the next layer protocol.
-- @param int Next layer protocol of the ip header as 8 bit integer.
function ip4Header:setProtocol(int)
	int = int or 0x11 	-- UDP
	self.protocol = int
end

--- Set the checksum.
-- @param int Checksum of the ip header as 16 bit integer.
-- @see ip4Header:calculateChecksum()
-- @see pkt:offloadUdpChecksum(ipv4, l2_len, l3_len)
function ip4Header:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Calculate and set the checksum.
-- If possible use checksum offloading instead.
-- @see pkt:offloadUdpChecksum(ipv4, l2_len, l3_len)
function ip4Header:calculateChecksum()
	self:setChecksum() -- just to be sure (packet may be reused); must be 0 
    self:setChecksum(hton16(checksum(self, 20)))
end

--- Set the destination address.
-- @param int Address in 'union ipv4_address' format.
function ip4Header:setDst(int)
	self.dst:set(int)
end

--- Set the source address.
-- @param int Address in 'union ipv4_address' format.
function ip4Header:setSrc(int)
	self.src:set(int)
end

--- Set the destination address.
-- @param str Address in string format.
function ip4Header:setDstString(str)
	self:setDst(parseIP4Address(str))
end

--- Set the source address.
-- @param str Address in string format.
function ip4Header:setSrcString(str)
	self:setSrc(parseIP4Address(str))
end

--- Set all members of the ip header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ipVersion, ipHeaderLength, ipTOS, ipLength, ipID, ipFragment, ipTTL, ipProtocol, ipChecksum, ipSrc, ipDst
-- @usage fill() -- only default values
-- @usage fill{ ipSrc="1.1.1.1", ipTTL=100 } -- all members are set to default values with the exception of ipSrc and ipTTL
function ip4Header:fill(args)
	self:setVersion(args.ipVersion)
	self:setHeaderLength(args.ipHeaderLength)
	self:setTOS(args.ipTOS)
	self:setLength(args.ipLength)
	self:setID(args.ipID)
	self:setFragment(args.ipFragment)
	self:setTTL(args.ipTTL)
	self:setProtocol(args.ipProtocol)
	self:setChecksum(args.ipChecksum)
	self:setSrcString(args.ipSrc or "192.168.1.1")
	self:setDstString(args.ipDst or "192.168.1.2")
end

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

	return self.uint32 + val
end

--- Add a number to an IPv4 address in-place.
-- Max. 32 bit.
-- @param val Number to add (32 bit integer).
function ip4Addr:add(val)
	self.uint32 = self.uint32 + val
end

--- Subtract a number from an IPv4 address.
-- Max. 32 bit.
-- @param val Number to substract (32 bit integer)
-- @return Resulting address in uint32 format.
function ip4Addr:__sub(val)
	return self + -val
end

--- ipv6 packets
local udp6PacketType = ffi.typeof("struct udp_v6_packet*")

--- Retrieve an IPv6 UDP packet.
-- @return Packet in 'struct udp_v6_packet' format.
function pkt:getUDP6Packet()
	return udp6PacketType(self.pkt.data)
end

local ip6Header = {}
ip6Header.__index = ip6Header

--- Set the version. 
-- @param int IP6 header version as 4 bit integer. Should always be '6'.
function ip6Header:setVersion(int)
	int = int or 6
	int = band(lshift(int, 28), 0xf0000000) -- fill to 32 bits
	
	old = bswap(self.vtf)
	old = band(old, 0x0fffffff)	-- remove old value
	
	self.vtf = bswap(bor(old, int))
end

--- Set the traffic class.
-- @param int Traffic class of the ip6 header as 8 bit integer.
function ip6Header:setTrafficClass(int)
	int = int or 0
	int = band(lshift(int, 20), 0x0ff00000)
	
	old = bswap(self.vtf)
	old = band(old, 0xf00fffff)
	
	self.vtf = bswap(bor(old, int))
end

--- Set the flow label.
-- @param int Flow label of the ip6 header as 20 bit integer.
function ip6Header:setFlowLabel(int)
	int = int or 0
	int = band(int, 0x000fffff)
	
	old = bswap(self.vtf)
	old = band(old, 0xfff00000)
	
	self.vtf = bswap(bor(old, int))
end

--- Set the payload length.
-- @param int Length of the ip6 header payload (hence, excluding l2 and l3 headers). 16 bit integer.
function ip6Header:setLength(int)
	int = int or 8	-- with eth + UDP -> minimum 66
	self.len = hton16(int)
end

--- Set the next header.
-- @param int Next header of the ip6 header as 8 bit integer.
function ip6Header:setNextHeader(int)
	int = int or 0x11	-- UDP
	self.nextHeader = int
end

--- Set the time-to-live (TTL).
-- @param int TTL of the ip6 header as 8 bit integer.
function ip6Header:setTTL(int)
	int = int or 64
	self.ttl = int
end

--- Set the destination address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Header:setDst(addr)
	self.dst:set(addr)
end

--- Set the source  address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Header:setSrc(addr)
	self.src:set(addr)
end

--- Set the destination address.
-- @param str Address in string format.
function ip6Header:setDstString(str)
	self:setDst(parseIP6Address(str))
end

--- Set the source address.
-- @param str Address in string format.
function ip6Header:setSrcString(str)
	self:setSrc(parseIP6Address(str))
end

--- Set all members of the ip6 header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ip6Version, ip6TrafficClass, ip6FlowLabel, ip6Length, ip6NextHeader, ip6TTL, ip6Src, ip6Dst
-- @usage fill() -- only default values
-- @usage fill{ ip6Src="f880::ab", ip6TTL=101 } -- all members are set to default values with the exception of ip6Src and ip6TTL
function ip6Header:fill(args)
	self:setVersion(args.ip6Version)
	self:setTrafficClass(args.ip6TrafficClass)
	self:setFlowLabel(args.ip6FlowLabel)
	self:setLength(args.ip6Length)
	self:setNextHeader(args.ip6NextHeader)
	self:setTTL(args.ip6TTL)
	self:setSrcString(args.ip6Src or "fe80::1")
	self:setDstString(args.ip6Dst or "fe80::2")
end

local ip6Addr = {}
ip6Addr.__index = ip6Addr
local ip6AddrType = ffi.typeof("union ipv6_address")

--- Retrieve the IPv6 address.
-- @return Address in 'union ipv6_address' format.
function ip6Addr:get()
	local addr = ip6AddrType()
	addr.uint32[0] = bswap(self.uint32[3])
	addr.uint32[1] = bswap(self.uint32[2])
	addr.uint32[2] = bswap(self.uint32[1])
	addr.uint32[3] = bswap(self.uint32[0])
	return addr
end

--- Set the IPv6 address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Addr:set(addr)
	self.uint32[0] = bswap(addr.uint32[3])
	self.uint32[1] = bswap(addr.uint32[2])
	self.uint32[2] = bswap(addr.uint32[1])
	self.uint32[3] = bswap(addr.uint32[0])
end

--- Set the IPv6 address.
-- @param ip Address in string format.
function ip6Addr:setString(ip)
	self:set(parseIP6Address(ip))
end

--- Test equality of two IPv6 addresses.
-- @param lhs Address in 'union ipv6_address' format.
-- @param rhs Address in 'union ipv6_address' format.
-- @return true if equal, false otherwise.
function ip6Addr.__eq(lhs, rhs)
	return istype(ip6AddrType, lhs) and istype(ip6AddrType, rhs) and lhs.uint64[0] == rhs.uint64[0] and lhs.uint64[1] == rhs.uint64[1]
end

--- Add a number to an IPv6 address.
-- Max. 64bit, commutative.
-- @param lhs Address in 'union ipv6_address' format.
-- @param rhs Number to add (64 bit integer).
-- @return Resulting address in 'union ipv6_address' format.
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

--- Add a number to an IPv6 address in-place.
-- Max 64 bit.
-- @param val Number to add (64 bit integer).
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

--- Subtract a number from an IPv6 address.
-- Max. 64 bit.
-- @param val Number to substract (64 bit integer).
-- @return Resulting address in 'union ipv6_address' format.
function ip6Addr:__sub(val)
	return self + -val
end

-- Retrieve the string representation of an IPv6 address.
-- Assumes 'union ipv6_address' is in network byteorder.
-- @param doByteSwap Optional change the byteorder of the ip6 address before returning the string representation.
-- @return Address in string format.
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
local udpHeader = {}
udpHeader.__index = udpHeader

--- Set the source port.
-- @param int Source port of the udp header as 16 bit integer.
function udpHeader:setSrcPort(int)
	int = int or 1024
	self.src = hton16(int)
end

--- Set the destination port.
-- @param int Destination port of the udp header as 16 bit integer.
function udpHeader:setDstPort(int)
	int = int or 1025
	self.dst = hton16(int)
end

--- Set the length.
-- @param int Length of the udp header plus payload (excluding l2 and l3). 16 bit integer.
function udpHeader:setLength(int)
	int = int or 28 -- with ethernet + IPv4 header -> 64B
	self.len = hton16(int)
end

--- Set the checksum.
-- @param int Checksum of the udp header as 16 bit integer.
function udpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Set all members of the udp header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: udpSrc, udpDst, udpLength, udpChecksum
-- @usage fill() -- only default values
-- @usage fill{ udpSrc=44566, ip6Length=101 } -- all members are set to default values with the exception of udpSrc and udpLength
function udpHeader:fill(args)
	self:setSrcPort(args.udpSrc)
	self:setDstPort(args.udpDst)
	self:setLength(args.udpLength)
	self:setChecksum(args.udpChecksum)
end

-- udp packets
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
-- @see etherHeader:fill()
-- @see ip4Header:fill()
-- @see udpHeader:fill()
function udpPacket:fill(args)
	-- calculate length values for all headers
	if args.pktLength then
		args.pktLength = args.pktLength - 4 -- CRC checksum gets appended by NIC
		args.ipLength = args.pktLength - 14 -- ethernet

		ipHeaderBytes = (args.ipHeaderLength or 5) * 4 -- ip_h can have variable size
		args.udpLength = args.pktLength - (14 + ipHeaderBytes) -- ethernet + ip
	end

	self.eth:fill(args)
	self.ip:fill(args)
	self.udp:fill(args)
end

--- Calculate and set the UDP header checksum for IPv4 packets.
-- Not implemented as it is optional.
-- If possible use checksum offloading instead.
-- @see pkt:offloadUdpChecksum()
function udpPacket:calculateUDPChecksum()
	-- optional, so don't do it
	self.udp:setChecksum()
end

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
-- @see etherHeader:fill()
-- @see ip6Header:fill()
-- @see udpHeader:fill()
function udp6Packet:fill(args)
	-- calculate length values for all headers
	if args.pktLength then
		args.pktLength = args.pktLength - 4 -- CRC checksum gets appended by NIC
		args.ip6Length = args.pktLength - (14 + 40) -- ethernet + ip
		args.udpLength = args.pktLength - (14 + 40) -- ethernet + ip
	end

	-- change some default values for ipv6
	args.ethType = args.ethType or 0x86dd
	args.udpLength = args.udpLength or 8

	self.eth:fill(args)
	self.ip:fill(args)
	self.udp:fill(args)
end

--- Calculate and set the UDP header checksum for IPv6 packets.
-- Not implemented (todo).
-- If possible use checksum offloading instead.
-- @see pkt:offloadUdpChecksum()
function udp6Packet:calculateUDPChecksum()
	-- TODO as it is mandatory for IPv6 UDP packets
	self.udp:setChecksum()
end

ffi.metatype("struct mac_address", macAddr)
ffi.metatype("struct ethernet_packet", etherPacket)
ffi.metatype("struct ethernet_header", etherHeader)

ffi.metatype("struct ipv4_header", ip4Header)
ffi.metatype("struct ipv6_header", ip6Header)
ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("union ipv6_address", ip6Addr)

ffi.metatype("struct udp_header", udpHeader)

ffi.metatype("struct udp_packet", udpPacket)
ffi.metatype("struct udp_v6_packet", udp6Packet)

ffi.metatype("struct rte_mbuf", pkt)

