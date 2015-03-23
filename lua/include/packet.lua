local ffi = require "ffi"

require "utils"
require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"

local eth = require "proto.ethernet"
local arp = require "proto.arp"
local ptp = require "proto.ptp"
local ip = require "proto.ip"
local ip6 = require "proto.ip6"
local icmp = require "proto.icmp"
local udp = require "proto.udp"
local tcp = require "proto.tcp"

local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype


-------------------------------------------------------------------------------------------
--- General functions
-------------------------------------------------------------------------------------------

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

function pkt:hasTimestamp()
	return bit.bor(self.ol_flags, dpdk.PKT_RX_IEEE1588_TMST) ~= 0
end

--- Set the time to wait before the packet is sent for software rate-controlled send methods.
-- @param delay the time to wait before this packet (in bytes, i.e. 1 == 0.8 nanoseconds on 10 GbE)
function pkt:setDelay(delay)
	self.pkt.hash.rss = delay
end

function pkt:setRate(rate)
	self.pkt.hash.rss = 10^10 / 8 / (rate * 10^6) - self.pkt.pkt_len - 24
end

--- Print a hex dump of the complete packet.
-- Dumps the first self.pkt_len bytes of self.data.
-- As this struct has no information about the actual type of the packet, it gets recreated by analyzing the protocol fields (etherType, protocol, ...).
-- The packet is then dumped using the dump method of the best fitting packet (starting with an ethernet packet and going up the layers).
-- TODO if packet was received print reception time instead
-- @see etherPacket:dump
-- @see ip4Packet:dump
-- @see udpPacket:dump
-- @see tcp.tcp4Packet:dump
function pkt:dump()
	local p = self:getEthernetPacket()
	local type = p.eth:getType()
	if type == eth.TYPE_ARP then
		-- ARP
		p = self:getArpPacket()
	elseif type == eth.TYPE_PTP then
		-- PTP
		p = self:getPtpPacket()
	elseif type == eth.TYPE_IP then
		-- ipv4
		p = self:getIPPacket()
		local proto = p.ip:getProtocol()

		if proto == ip.PROTO_ICMP then
			-- ICMPv4
			p = self:getIcmpPacket()
		elseif proto == ip.PROTO_UDP then
			-- UDPv4
			p = self:getUdpPacket()
		elseif proto == ip.PROTO_TCP then
			-- TCPv4
			p = self:getTcpPacket()
		end
	elseif type == eth.TYPE_IP6 then
		-- IPv6
		p = self:getIP6Packet()
		local proto = p.ip:getNextHeader()
		
		if proto == ip6.PROTO_ICMP then
			-- ICMPv6
			p = self:getIcmp6Packet()
		elseif proto == ip6.PROTO_UDP then
			-- UDPv6
			p = self:getUdp6Packet()
		elseif proto == ip6.PROTO_TCP then
			-- TCPv6
			p = self:getTcp6Packet()
		end
	end
	p:dump(self.pkt.pkt_len)
end


-------------------------------------------------------------------------------------------------------
--- Checksum offloading
-------------------------------------------------------------------------------------------------------

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
		dpdkc.calc_ipv4_pseudo_header_checksum(self.pkt.data, 20)
	else 
		l3_len = l3_len or 40
		self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_UDP_CKSUM)
		self.pkt.header_lengths = l2_len * 512 + l3_len
		-- calculate pseudo header checksum because the NIC doesn't do this...
		dpdkc.calc_ipv6_pseudo_header_checksum(self.pkt.data, 30)
	end
end

--- Instruct the NIC to calculate the IP and TCP checksum for this packet.
-- @param ipv4 Boolean to decide whether the packet uses IPv4 (set to nil/true) or IPv6 (set to anything else).
-- @param l2_len Length of the layer 2 header in bytes (default 14 bytes for ethernet).
-- @param l3_len Length of the layer 3 header in bytes (default 20 bytes for IPv4, 40 bytes for IPv6).
function pkt:offloadTcpChecksum(ipv4, l2_len, l3_len)
	-- NOTE: this method cannot be moved to the udpPacket class because it doesn't (and can't) know the pktbuf it belongs to
	ipv4 = ipv4 == nil or ipv4
	l2_len = l2_len or 14
	if ipv4 then
		l3_len = l3_len or 20
		self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_IPV4_CSUM, dpdk.PKT_TX_TCP_CKSUM)
		self.pkt.header_lengths = l2_len * 512 + l3_len
		-- calculate pseudo header checksum because the NIC doesn't do this...
		dpdkc.calc_ipv4_pseudo_header_checksum(self.pkt.data, 25)
	else 
		l3_len = l3_len or 40
		self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_TCP_CKSUM)
		self.pkt.header_lengths = l2_len * 512 + l3_len
		-- calculate pseudo header checksum because the NIC doesn't do this...
		dpdkc.calc_ipv6_pseudo_header_checksum(self.pkt.data, 35)
	end
end

function pkt:enableTimestamps()
	self.ol_flags = bit.bor(self.ol_flags, dpdk.PKT_TX_IEEE1588_TMST)
end

-------------------------------------------------------------------------------------------
--- Return packet as XYZ
-------------------------------------------------------------------------------------------

local etherPacketType = ffi.typeof("struct ethernet_packet*")
--- Retrieve an ethernet packet.
-- @return Packet in 'struct ethernet_packet' format
function pkt:getEthernetPacket()
	return etherPacketType(self.pkt.data)
end

local arpPacketType = ffi.typeof("struct arp_packet*")
--- Retrieve an ARP packet.
-- @return Packet in 'struct arp_packet' format
function pkt:getArpPacket()
	return arpPacketType(self.pkt.data)
end

local ptpPacketType = ffi.typeof("struct ptp_packet*")
--- Retrieve an PTP packet.
-- @return Packet in 'struct ptp_packet' format
function pkt:getPtpPacket()
	return ptpPacketType(self.pkt.data)
end

local ip4PacketType = ffi.typeof("struct ip_packet*")
--- Retrieve an IP4 packet.
-- @return Packet in 'struct ip_packet' format
function pkt:getIP4Packet()
	return ip4PacketType(self.pkt.data)
end

local ip6PacketType = ffi.typeof("struct ip_v6_packet*")
--- Retrieve an IP6 packet.
-- @return Packet in 'struct ip_v6_packet' format
function pkt:getIP6Packet()
	return ip6PacketType(self.pkt.data)
end

--- Retrieve either an IPv4 or IPv6 packet.
-- @param ipv4 If true or nil returns IPv4, IPv6 otherwise
-- @return Packet in 'struct ip_packet' or 'struct ip_v6_packet' format
function pkt:getIPPacket(ipv4)
	ipv4 = ipv4 == nil or ipv4
	if ipv4 then
		return self:getIP4Packet()
	else
		return self:getIP6Packet()
	end
end

local icmp4PacketType = ffi.typeof("struct icmp_packet*")
--- Retrieve an ICMPv4 packet.
-- @return Packet in 'struct icmp_packet' format
function pkt:getIcmp4Packet()
	return icmp4PacketType(self.pkt.data)
end

local icmp6PacketType = ffi.typeof("struct icmp_v6_packet*")
--- Retrieve an ICMPv6 packet.
-- @return Packet in 'struct icmp_v6_packet' format
function pkt:getIcmp6Packet()
	return icmp6PacketType(self.pkt.data)
end

--- Retrieve either an ICMPv4 or ICMPv6 packet.
-- @return ipv4 If true or nil returns ICMPv4, ICMPv6 otherwise
-- @return Packet in 'struct icmp_packet' or 'struct icmp_v6_packet' format
function pkt:getIcmpPacket(ipv4)
	ipv4 = ipv4 == nil or ipv4
	if ipv4 then
		return self:getIcmp4Packet()
	else
		return self:getIcmp6Packet()
	end
end

local udpPacketType = ffi.typeof("struct udp_packet*")
--- Retrieve an IPv4 UDP packet.
-- @return Packet in 'struct udp_packet' format.
function pkt:getUdp4Packet()
	return udpPacketType(self.pkt.data)
end

local udp6PacketType = ffi.typeof("struct udp_v6_packet*")
--- Retrieve an IPv6 UDP packet.
-- @return Packet in 'struct udp_v6_packet' format.
function pkt:getUdp6Packet()
	return udp6PacketType(self.pkt.data)
end

--- Retrieve either an UDPv4 or UDPv6 packet.
-- @return ipv4 If true or nil returns UDPv4, UDPv6 otherwise
-- @return Packet in 'struct udp_packet' or 'struct udp_v6_packet' format
function pkt:getUdpPacket(ipv4)
	ipv4 = ipv4 == nil or ipv4
	if ipv4 then
		return self:getUdp4Packet()
	else
		return self:getUdp6Packet()
	end
end

local tcp4PacketType = ffi.typeof("struct tcp_packet*")
--- Retrieve an TCPv4 packet.
-- @return Packet in 'struct tcp_packet' format
function pkt:getTcp4Packet()
	return tcp4PacketType(self.pkt.data)
end

local tcp6PacketType = ffi.typeof("struct tcp_v6_packet*")
--- Retrieve an TCPv6 packet.
-- @return Packet in 'struct tcp_v6_packet' format
function pkt:getTcp6Packet()
	return tcp6PacketType(self.pkt.data)
end

--- Retrieve either an TCPv4 or TCPv6 packet.
-- @return ipv4 If true or nil returns TCPv4, TCPv6 otherwise
-- @return Packet in 'struct tcp_packet' or 'struct tcp_v6_packet' format
function pkt:getTcpPacket(ipv4)
	ipv4 = ipv4 == nil or ipv4
	if ipv4 then
		return self:getTcp4Packet()
	else
		return self:getTcp6Packet()
	end
end


---------------------------------------------------------------------------
---- Metatypes
---------------------------------------------------------------------------

ffi.metatype("struct rte_mbuf", pkt)

