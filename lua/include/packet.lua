local ffi = require "ffi"

require "utils"
require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local ip = require "ip"
local ip6 = require "ip6"
local eth = require "ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local write = io.write
local format = string.format

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

--- Set the time to wait before the packet is sent for software rate-controlled send methods.
-- @param delay the time to wait before this packet (in bytes, i.e. 1 == 0.8 nanoseconds on 10 GbE)
function pkt:setDelay(delay)
	self.pkt.hash.rss = delay
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

--- Instruct the NIC to calculate the IP checksum for this packet.
-- @param ipv4 Boolean to decide whether the packet uses IPv4 (set to nil/true) or IPv6 (set to anything else).
-- 			   In case it is an IPv6 packet, do nothing (the header has no checksum).
-- @param l2_len Length of the layer 2 header in bytes (default 14 bytes for ethernet).
-- @param l3_len Length of the layer 3 header in bytes (default 20 bytes for IPv4).
function pkt:offloadIPChecksum(ipv4, l2_len, l3_len)
	-- NOTE: this method cannot be moved to the udpPacket class because it doesn't (and can't) know the pktbuf it belongs to
	ipv4 = ipv4 == nil or ipv4
	if ipv4 then
		l2_len = l2_len or 14
		l3_len = l3_len or 20
		self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_IPV4_CSUM)
		self.pkt.header_lengths = l2_len * 512 + l3_len
	end
end

--- Print a hex dump of the complete packet.
-- Dumps the first self.pkt_len bytes of self.data.
-- As this struct has no information about the actual type of the packet, it gets recreated by analyzing the protocol fields (etherType, protocol, ...).
-- The packet is then dumped using the dump method of the best fitting packet (starting with an ethernet packet and going up the layers).
-- TODO if packet was received print reception time instead
-- @see etherPacket:dump
-- @see ip4Packet:dump
-- @see udpPacket:dump
function pkt:dump()
	local p = self:getEthernetPacket()
	if p.eth:getType() == eth.TYPE_IP then
		-- ipv4
		p = self:getIPPacket()
		if p.ip:getProtocol() == ip.PROTO_UDP then
			-- UDPv4
			p = self:getUdpPacket()
		end
	elseif p.eth:getType() == eth.TYPE_IP6 then
		-- IPv6
		p = self:getIP6Packet()
		if p.ip:getNextHeader() == ip6.PROTO_UDP then
			-- UDPv6
			p = self:getUdp6Packet()
		end
	end
	p:dump(self.pkt.pkt_len)
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
	self:set(parseMacAddress(mac))
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

--- Retrieve the destination MAC address.
-- @return Address in 'struct mac_address' format.
function etherHeader:getDst(addr)
	return self.dst:get()
end

--- Set the source MAC address.
-- @param addr Address in 'struct mac_address' format.
function etherHeader:setSrc(addr)
	self.src:set(addr)
end

--- Retrieve the source MAC address.
-- @return Address in 'struct mac_address' format.
function etherHeader:getSrc(addr)
	return self.src:get()
end

--- Set the destination MAC address.
-- @param str Address in string format.
function etherHeader:setDstString(str)
	self.dst:setString(str)
end

--- Retrieve the destination MAC address.
-- @return Address in string format.
function etherHeader:getDstString()
	return self.dst:getString()
end

--- Set the source MAC address.
-- @param str Address in string format.
function etherHeader:setSrcString(str)
	self.src:setString(str)
end

--- Retrieve the source MAC address.
-- @return Address in string format.
function etherHeader:getSrcString()
	return self.src:getString()
end

--- Set the EtherType.
-- @param int EtherType as 16 bit integer.
function etherHeader:setType(int)
	int = int or eth.TYPE_IP
	self.type = hton16(int)
end

--- Retrieve the EtherType.
-- @return EtherType as 16 bit integer.
function etherHeader:getType()
	return hton16(self.type)
end

--- Retrieve the ether type.
-- @return EtherType as string.
function etherHeader:getTypeString()
	local type = self:getType()
	local cleartext = ""
	
	if type == eth.TYPE_IP then
		cleartext = "(IP4)"
	elseif type == eth.TYPE_IP6 then
		cleartext = "(IP6)"
	elseif type == eth.TYPE_ARP then
		cleartext = "(ARP)"
	else
		cleartext = "(unknown)"
	end

	return format("0x%04x %s", type, cleartext)
end

--- Set all members of the ethernet header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ethSrc, ethDst, ethType
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ethType=0x137 } -- default value for ethDst; ethSrc and ethType user-specified
function etherHeader:fill(args)
	args = args or {}

	args.ethSrc = args.ethSrc or "01:02:03:04:05:06"
	args.ethDst = args.ethDst or "07:08:09:0a:0b:0c"
	
	-- if for some reason the address is in 'struct mac_address' format, cope with it
	if type(args.ethSrc) == "string" then
		self:setSrcString(args.ethSrc)
	else
		self:setSrc(args.ethSrc)
	end
	if type(args.ethDst) == "string" then
		self:setDstString(args.ethDst)
	else
		self:setDst(args.ethDst)
	end
	self:setType(args.ethType)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:fill
function etherHeader:get()
	return { ethSrc=self:getSrcString(), ethDst=self:getDstString(), ethType=self:getType() }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function etherHeader:getString()
	return "ETH " .. self:getSrcString() .. " > " .. self:getDstString() .. " type " .. self:getTypeString() .. " "
end

--- Layer 2 packet
local etherPacketType = ffi.typeof("struct ethernet_packet*")
local etherPacket = {}
etherPacket.__index = etherPacket

--- Set all members of the ethernet header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67" } -- all members are set to default values with the exception of ethSrc
-- @see etherHeader:fill
function etherPacket:fill(args)
	args = args or {}

	self.eth:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
function etherPacket:get()
	return self.eth:get()
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function etherPacket:dump(bytes)
	str = getTimeMicros() .. self.eth:getString()
	printLength(str, 60)
	dumpHex(self, bytes)
end

--- Retrieve an ethernet packet.
-- @return Packet in 'struct ethernet_packet' format
function pkt:getEthernetPacket()
	return etherPacketType(self.pkt.data)
end


---ip packets
local udpPacketType = ffi.typeof("struct udp_packet*")

--- Retrieve an IPv4 UDP packet.
-- @return Packet in 'struct udp_packet' format.
function pkt:getUdpPacket()
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

--- ipv6 packets
local udp6PacketType = ffi.typeof("struct udp_v6_packet*")

--- Retrieve an IPv6 UDP packet.
-- @return Packet in 'struct udp_v6_packet' format.
function pkt:getUdp6Packet()
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

--- Retrieve the version.
-- @return Version as 4 bit integer.
function ip6Header:getVersion()
	return band(rshift(bswap(self.vtf), 28), 0x0000000f)
end

--- Retrieve the version.
-- @return Version as string.
function ip6Header:getVersionString()
	return self:getVersion()
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

--- Retrieve the traffic class.
-- @return Traffic class as 8 bit integer.
function ip6Header:getTrafficClass()
	return band(rshift(bswap(self.vtf), 20), 0x000000ff)
end

--- Retrieve the traffic class.
-- @return Traffic class as string.
function ip6Header:getTrafficClassString()
	return self:getTrafficClass()
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

--- Retrieve the flow label.
-- @return Flow label as 20 bit integer.
function ip6Header:getFlowLabel()
	return band(bswap(self.vtf), 0x000fffff)
end

--- Retrieve the flow label.
-- @return Flow label as string.
function ip6Header:getFlowLabelString()
	return self:getFlowLabel()
end

--- Set the payload length.
-- @param int Length of the ip6 header payload (hence, excluding l2 and l3 headers). 16 bit integer.
function ip6Header:setLength(int)
	int = int or 8	-- with eth + UDP -> minimum 66
	self.len = hton16(int)
end

--- Retrieve the length.
-- @return Length as 16 bit integer.
function ip6Header:getLength()
	return hton16(self.len)
end

--- Retrieve the length.
-- @return Length as string.
function ip6Header:getLengthString()
	return self:getLength()
end

--- Set the next header.
-- @param int Next header of the ip6 header as 8 bit integer.
function ip6Header:setNextHeader(int)
	int = int or ip6.PROTO_UDP
	self.nextHeader = int
end

--- Retrieve the next header.
-- @return Next header as 8 bit integer.
function ip6Header:getNextHeader()
	return self.nextHeader
end

--- Retrieve the next header.
-- @return Next header as string.
function ip6Header:getNextHeaderString()
	local proto = self:getNextHeader()
	local cleartext = ""
	
	if proto == ip6.PROTO_UDP then
		cleartext = "(UDP)"
	elseif proto == ip6.PROTO_TCP then
		cleartext = "(TCP)"
	else
		cleartext = "(unknown)"
	end
	
	return format("0x%02x %s", proto, cleartext)
end

--- Set the time-to-live (TTL).
-- @param int TTL of the ip6 header as 8 bit integer.
function ip6Header:setTTL(int)
	int = int or 64
	self.ttl = int
end

--- Retrieve the time-to-live.
-- @return TTL as 8 bit integer.
function ip6Header:getTTL()
	return self.ttl
end

--- Retrieve the time-to-live.
-- @return TTL as string.
function ip6Header:getTTLString()
	return self:getTTL()
end

--- Set the destination address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Header:setDst(addr)
	self.dst:set(addr)
end

--- Retrieve the IP6 destination address.
-- @return Address in 'union ipv6_address' format.
function ip6Header:getDst()
	return self.dst:get()
end

--- Set the source  address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Header:setSrc(addr)
	self.src:set(addr)
end

--- Retrieve the IP6 source address.
-- @return Address in 'union ipv6_address' format.
function ip6Header:getSrc()
	return self.src:get()
end

--- Set the destination address.
-- @param str Address in string format.
function ip6Header:setDstString(str)
	self:setDst(parseIP6Address(str))
end

--- Retrieve the IP6 destination address.
-- @return Address in string format.
function ip6Header:getDstString()
	return self.dst:getString()
end

--- Set the source address.
-- @param str Address in string format.
function ip6Header:setSrcString(str)
	self:setSrc(parseIP6Address(str))
end

--- Retrieve the IP6 source address.
-- @return Address in source format.
function ip6Header:getSrcString()
	return self.src:getString()
end

--- Set all members of the ip6 header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ip6Version, ip6TrafficClass, ip6FlowLabel, ip6Length, ip6NextHeader, ip6TTL, ip6Src, ip6Dst
-- @usage fill() -- only default values
-- @usage fill{ ip6Src="f880::ab", ip6TTL=101 } -- all members are set to default values with the exception of ip6Src and ip6TTL
function ip6Header:fill(args)
	args = args or {}

	self:setVersion(args.ip6Version)
	self:setTrafficClass(args.ip6TrafficClass)
	self:setFlowLabel(args.ip6FlowLabel)
	self:setLength(args.ip6Length)
	self:setNextHeader(args.ip6NextHeader)
	self:setTTL(args.ip6TTL)
	
	args.ip6Src = args.ip6Src or "fe80::1"
	args.ip6Dst = args.ip6Dst or "fe80::2"	
	
	-- if for some reason the address is in 'union ipv6_address' format, cope with it
	if type(args.ip6Src) == "string" then
		self:setSrcString(args.ip6Src)
	else
		self:setSrc(args.ip6Src)
	end
	if type(args.ip6Dst) == "string" then
		self:setDstString(args.ip6Dst)
	else
		self:setDst(args.ip6Dst)
	end
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see ip6Header:fill
function ip6Header:get()
	return { ip6Src=self:getSrcString(), ip6Dst=self:getDstString(), ip6Version=self:getVersion(), ip6TrafficClass=self:getTrafficClass(), 
			 ip6FlowLabel=self:getFlowLabel(), ip6Length=self:getLength(), ip6NextHeader=self:getNextHeader(), ip6TTL=self:getTTL() }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function ip6Header:getString()
	return "IP6 " .. self:getSrcString() .. " > " .. self:getDstString() .. " ver " .. self:getVersionString() 
		   .. " tc " .. self:getTrafficClassString() .. " fl " .. self:getFlowLabelString() .. " len " .. self:getLengthString() 
		   .. " next " .. self:getNextHeaderString() .. " ttl " .. self:getTTLString() .. " "
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

-- ip packets
local ip4Packet = {}
local ip4PacketType = ffi.typeof("struct ip_packet*")
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

--- Retrieve an IP4 packet.
-- @return Packet in 'struct ip_packet' format
function pkt:getIPPacket()
	return ip4PacketType(self.pkt.data)
end

local ip6Packet = {}
local ip6PacketType = ffi.typeof("struct ip_v6_packet*")
ip6Packet.__index = ip6Packet

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set the length member of the ip6 header.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ip6TTL=100 } -- all members are set to default values with the exception of ethSrc and ip6TTL
-- @usage fill{ pktLength=64 } -- only default values, ip6Length is set to the respective value
-- @see etherHeader:fill
-- @see ip6Header:fill
function ip6Packet:fill(args)
	args = args or {}
	
	-- calculate length value for ip headers
	if args.pktLength then
		args.ip6Length = args.pktLength - (14 + 40) -- ethernet + ip
	end
	
	-- change default value for ipv6
	args.ethType = args.ethType or eth.TYPE_IP6

	self.eth:fill(args)
	self.ip:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip6Header:get
function ip6Packet:get()
	return mergeTables(self.eth:get(), self.ip:get())
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function ip6Packet:dump(bytes)
	str = getTimeMicros() .. self.eth:getString() .. self.ip:getString()
	printLength(str, 60)
	dumpHex(self, bytes)
end

--- Retrieve an IP6 packet.
-- @return Packet in 'struct ip_v6_packet' format
function pkt:getIP6Packet()
	return ip6PacketType(self.pkt.data)
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
		   .. " cksum " .. self:getChecksumString() .. " "
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
-- @see etherHeader:fill
-- @see ip4Header:fill
-- @see udpHeader:fill
function udpPacket:fill(args)
	args = args or {}
	
	-- calculate length values for all headers
	if args.pktLength then
		args.ipLength = args.pktLength - 14 -- ethernet

		ipHeaderBytes = (args.ipHeaderLength or 5) * 4 -- ip_h can have variable size
		args.udpLength = args.pktLength - (14 + ipHeaderBytes) -- ethernet + ip
	end

	self.eth:fill(args)
	self.ip:fill(args)
	self.udp:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip4Header:get
-- @see udpHeader:get
function udpPacket:get()
	return mergeTables(mergeTables(self.eth:get(), self.ip:get()), self.udp:get())
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
	str = getTimeMicros() .. self.eth:getString() .. self.ip:getString() .. self.udp:getString()
	printLength(str, 60)
	dumpHex(self, bytes)
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
-- @see etherHeader:fill
-- @see ip6Header:fill
-- @see udpHeader:fill
function udp6Packet:fill(args)
	args = args or {}

	-- calculate length values for all headers
	if args.pktLength then
		args.ip6Length = args.pktLength - (14 + 40) -- ethernet + ip
		args.udpLength = args.pktLength - (14 + 40) -- ethernet + ip
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
	return mergeTables(mergeTables(self.eth:get(), self.ip:get()), self.udp:get())
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
	str = getTimeMicros() .. self.eth:getString() .. self.ip:getString() .. self.udp:getString()
	printLength(str, 60)
	dumpHex(self, bytes)
end

ffi.metatype("struct mac_address", macAddr)
ffi.metatype("struct ethernet_packet", etherPacket)
ffi.metatype("struct ethernet_header", etherHeader)

ffi.metatype("struct ip_packet", ip4Packet)
ffi.metatype("struct ip_v6_packet", ip6Packet)
ffi.metatype("struct ipv4_header", ip4Header)
ffi.metatype("struct ipv6_header", ip6Header)
ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("union ipv6_address", ip6Addr)

ffi.metatype("struct udp_header", udpHeader)

ffi.metatype("struct udp_packet", udpPacket)
ffi.metatype("struct udp_v6_packet", udp6Packet)

ffi.metatype("struct rte_mbuf", pkt)

