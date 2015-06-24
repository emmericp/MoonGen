local ffi = require "ffi"

require "utils"
require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"

local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local write = io.write


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

--- Check if the PKT_RX_IEEE1588_TMST flag is set
-- Turns out that this flag is pretty pointless, it does not indicate
-- if the packet was actually timestamped, just that it came from a
-- queue/filter with timestamping enabled.
-- You probably want to use device:hasTimestamp() and check the sequence number.
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

function pkt:setSize(size)
	self.pkt.pkt_len = size
	self.pkt.data_len = size
end

--- Returns the packet data cast to the best fitting packet struct (starting with ethernet header)
-- @return packet data as cdata of best fitting packet
function pkt:get()
	return self:getEthernetPacket():resolveLastHeader()
end

--- Dumps the packet data cast to the best fitting packet struct
-- @param bytes number of bytes to dump, optional
function pkt:dump(bytes)
	self:get():dump(bytes or self.pkt.pkt_len)
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


----------------------------------------------------------------------------------
--- Create new packet type
----------------------------------------------------------------------------------

-- functions of the packet
local packetGetHeaders
local packetGetHeader
local packetDump
local packetFill
local packetGet
local packetResolveLastHeader
local packetCalculateChecksums
local packetMakeStruct

--- Create struct and functions for a new packet
-- For implemented headers (see proto/) these packets are defined in the section 'Packet struct' of each protocol file
-- @param args list of keywords (see makeStruct)
-- @return returns the constructor/cast function for this packet
-- @see makeStruct
function packetCreate(...)
	local args = { ... }
	
	local packet = {}
	packet.__index = packet

	-- create struct
	local packetName, ctype = packetMakeStruct(args)

	--- functions of the packet
	packet.getArgs = function() return args end
	
	packet.getName = function() return packetName end

	packet.getHeaders = packetGetHeaders

	packet.getHeader = packetGetHeader 

	packet.dump = packetDump
	
	packet.fill = packetFill

	packet.get = packetGet

	packet.resolveLastHeader = packetResolveLastHeader

	packet.setLength = packetSetLength

	-- functions for manual (not offloaded) checksum calculations
	packet.calculateChecksums = packetCalculateChecksums
	
	for _, v in ipairs(args) do
		local header, member
		if type(v) == "table" then
			header = v[1]
			member = v[2]
		else
			header = v
			member = v
		end
		-- if the header has a checksum, add a function to calculate it
		if header == "ip4" or header == "icmp" then -- FIXME NYI or header == "udp" or header == "tcp" then
			local key = 'calculate' .. member:gsub("^.", string.upper) .. 'Checksum'
			packet[key] = function(self) self:getHeader(v):calculateChecksum() end
		end
	end


	-- add functions to packet
	ffi.metatype(packetName, packet)

	-- return 'get'/'cast' for this kind of packet
	return function(self) return ctype(self.pkt.data) end
end

--- Get all headers of a packet as list
-- @param self The packet
-- @return Table of members of the packet
function packetGetHeaders(self) 
	local headers = {} 
	for i, v in ipairs(self:getArgs()) do 
		headers[i] = packetGetHeader(self, v) 
	end 
	return headers 
end

--- Get the specified header of a packet (e.g. self.eth)
-- @param self the packet (cdata)
-- @param h header to be returned
-- @return The member of the packet
function packetGetHeader(self, h)
	local proto, member
	if type(h) == "table" then
		member = h[2]
	else
		member = h
	end
	return self[member]
end

--- Print a hex dump of a packet.
-- @param self the packet
-- @param bytes Number of bytes to dump. If no size is specified the payload is truncated.
function packetDump(self, bytes) 
	bytes = bytes or ffi.sizeof(self:getName())

	-- print timestamp
	write(getTimeMicros())

	-- headers in cleartext
	for i, v in ipairs(self:getHeaders()) do
		local str = v:getString()
		if i == 1 then write(" " .. str .. "\n") else print(str) end
	end

	-- hex dump
	dumpHex(self, bytes)
end
	
--- Set all members of all headers.
-- Note: this function is slow. If you want to modify members of a header during a time critical section of your script use the respective setters.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set the length member of headers (e.g. ip header).
-- @param self The packet
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ipTTL=100 } -- all members are set to default values with the exception of ethSrc and ipTTL
-- @usage fill{ pktLength=64 } -- only default values, length members of the headers are adjusted
function packetFill(self, namedArgs) 
	-- fill headers
	local headers = self:getHeaders()
	local args = self:getArgs()
	local accumulatedLength = 0
	for i, v in ipairs(headers) do
		local curMember = args[i]
		if type(curMember) == "table" then
			curMember = curMember[2]
		end
		local nextHeader = args[i + 1]
		if type(nextHeader) == "table" then
			nextHeader = nextHeader[1]
		end
		namedArgs = v:setDefaultNamedArgs(curMember, namedArgs, nextHeader, accumulatedLength)
		v:fill(namedArgs, curMember) 

		accumulatedLength = accumulatedLength + ffi.sizeof(v)
	end
end

--- Retrieve the values of all members as list of named arguments.
-- @param self The packet
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see packetFill
function packetGet(self) 
	local namedArgs = {} 
	local args = self:getArgs()
	for i, v in ipairs(self:getHeaders()) do 
		local member = args[i]
		if type(member) == "table" then
			member = member[2]
		end
		namedArgs = mergeTables(namedArgs, v:get(member)) 
	end 
	return namedArgs 
end

--- Try to find out what the next header in the payload of this packet is
-- This function is only used for buf:get/buf:dump
-- @param self The packet
function packetResolveLastHeader(self)
	local name = self:getName()
	local headers = self:getHeaders()
	local next_header = headers[#headers]:resolveNextHeader()
	
	if not next_header then
		return self
	else
		next_member = next_header
		
		if next_header == "ethernet" then
			next_member = "eth"
		end
		-- TODO if same header exists multiple times rename member
		name = name .. "__" .. next_header .. "_" .. next_member .. "*"
		-- TODO if packet does not exist, create it
		return ffi.cast(name, self):resolveLastHeader()
	end
end

--- Set length for all headers.
-- Necessary when sending variable sized packets.
-- TODO runtime critical function: this has to be fast (check with benchmark)
-- @param self The packet
-- @param length Length of the packet. Value for respective length member of headers get calculated using this value.
function packetSetLength(self, length)
	local accumulatedLength = 0
	for _, v in ipairs(self:getArgs()) do
		local header, member
		if type(v) == "table" then
			header = v[1]
			member = v[2]
		else
			header = v
			member = v
		end
		if header == "ip4" or header == "udp" or header == "ptp" then
			self[member]:setLength(length - accumulatedLength)
		elseif header == "ip6" then
			self[member]:setLength(length - (accumulatedLength + 40))
		end
		accumulatedLength = accumulatedLength + ffi.sizeof(self[member])
	end
end

--- Calculate all checksums manually (not offloading them)
-- There also exist functions to calculate the checksum of only one header.
-- Naming convention: pkt:calculate<member>Checksum() (for all existing packets member = {Ip, Tcp, Udp, Icmp})
-- TODO runtime critical function: this has to be fast (check with benchmark)
function packetCalculateChecksums(self)
	for _, v in ipairs(self:getArgs()) do
		local header, member
		if type(v) == "table" then
			header = v[1]
			member = v[2]
		else
			header = v
			member = v
		end
		
		-- if the header has a checksum, call the function
		if header == "ip4" or header == "icmp" then -- FIXME NYI or header == "udp" or header == "tcp" then
			self:getHeader(v):calculateChecksum()
		end
	end
end

--- Creates a packet struct (cdata) consisting of different headers
-- simply list the headers in the order you want them to be in a packet
-- if you want the member to be named differently, use the following syntax
-- normal: <header>  different membername: { <header>, <member> }
-- supported keywords: eth, arp, ptp, ip, ip6, udp, tcp, icmp
-- e.g. makeStruct('eth', { 'ip4', 'ip' }, 'udp') creates an UDP packet struct
-- @param args list of keywords/tables of keyword-member pairs
-- @return name name of the struct
-- @return ctype ctype of the struct
function packetMakeStruct(...)
	local name = ""
	local str = ""
	
	-- add the specified headers and build the name
	for _, v in ipairs(...) do
		local header, member
		if type(v) == "table" then
			header = v[1]
			member = v[2]
		else
			header = v
			member = v
		end

		-- alias for eth -> ethernet
		if header == 'eth' then
			header = 'ethernet'
		end

		-- add header
		str = str .. [[
		struct ]] .. header .. '_header ' .. member .. [[;
		]]

		-- build name
		name = name .. "__" .. header .. "_" .. member
	end

	-- add rest of the struct
	str = [[
	struct __attribute__((__packed__)) ]] 
	.. name 
	.. [[ {
		]]
	.. str 
	.. [[
		union payload_t payload;
	};	
	]]
	-- add struct definition, return full name and typeof
	ffi.cdef(str)
	name = "struct " .. name
	return name, ffi.typeof(name .. "*")
end


---------------------------------------------------------------------------
---- Metatypes
---------------------------------------------------------------------------

ffi.metatype("struct rte_mbuf", pkt)

return pkt
