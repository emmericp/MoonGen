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

--- Retrieves the time stamp information
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

---ip packets
local udpPacketType = ffi.typeof("struct udp_packet*")

function pkt:getUDPPacket()
	return udpPacketType(self.pkt.data)
end

local ip4Header = {}
ip4Header.__index = ip4Header

function ip4Header:calculateChecksum()
	self.cs = 0 --just to be sure...
	self.cs = checksum(self, 20)
end

local ip4Addr = {}
ip4Addr.__index = ip4Addr

function ip4Addr:get()
	return bswap(self.uint32)
end

function ip4Addr:set(ip)
	self.uint32 = bswap(ip)
end

function parseIPAddress(ip)
	local bytes = {}
	bytes = {string.match(ip, '(%d+)%.(%d+)%.(%d+)%.(%d+)')}
	if bytes == nil then
		return
	end
	for i = 1, 4 do
		if bytes[i] == nil then
			return 
		end
		bytes[i] = tonumber(bytes[i])
		if  bytes[i] < 0 or bytes[i] > 255 then
			return
		end
	end
	
	ip = bytes[1]
	for i = 2, 4 do
		ip = bor(lshift(ip, 8), bytes[i])
	
	end
	return  ip 
end

function ip4Addr:getString()
	return ("%d.%d.%d.%d"):format(self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3])
end

--- ipv6 packets
local udp6PacketType = ffi.typeof("struct udp_v6_packet*")

function pkt:getUDP6Packet()
	return udp6PacketType(self.pkt.data)
end

local ip6Addr = {}
ip6Addr.__index = ip6Addr
local ip6AddrType = ffi.typeof("union ipv6_address")

function ip6Addr:get()
	local addr = ip6AddrType()
	addr.uint32[0] = bswap(self.uint32[3])
	addr.uint32[1] = bswap(self.uint32[2])
	addr.uint32[2] = bswap(self.uint32[1])
	addr.uint32[3] = bswap(self.uint32[0])
	return addr
end

function ip6Addr:set(addr)
	self.uint32[0] = bswap(addr.uint32[3])
	self.uint32[1] = bswap(addr.uint32[2])
	self.uint32[2] = bswap(addr.uint32[1])
	self.uint32[3] = bswap(addr.uint32[0])
end

function ip6Addr.__eq(lhs, rhs)
	return istype(ip6AddrType, lhs) and istype(ip6AddrType, rhs) and lhs.uint64[0] == rhs.uint64[0] and lhs.uint64[1] == rhs.uint64[1]
end

--- add a number to an IPv6 address
-- max. 64bit
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
	if low < val and val > 0 then
		high = high + 1
	elseif low > -val and val < 0 then
		high = high - 1
	end
	addr.uint64[0] = low
	addr.uint64[1] = high
	return addr
end

function ip6Addr:__sub(val)
	return self + -val
end

function parseIP6Address(ip)
	-- TODO: better parsing (shortened addresses)
	local bytes = { ip:match('(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x)') }
	if #bytes ~= 16 then
		error("bad IPv6 format")
	end
	for i, v in ipairs(bytes) do
		bytes[i] = tonumber(bytes[i], 16)
	end
	local addr = ffi.new("union ipv6_address")
	local uint32
	for i = 0, 3 do
		uint32 = bytes[1 + i * 4]
		for b = 2, 4 do
			uint32 = bor(lshift(uint32, 8), bytes[b + i * 4])
		end
		addr.uint32[3 - i] = uint32
	end
	return addr
end

function ip6Addr:getString()
	return ("%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x"):format(self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3], 
								  self.uint8[4], self.uint8[5], self.uint8[6], self.uint8[7], 
								  self.uint8[8], self.uint8[9], self.uint8[10], self.uint8[11], 
								  self.uint8[12], self.uint8[13], self.uint8[14], self.uint8[15])
end

-- udp

local udpHeader = {}
udpHeader.__index = udpHeader

function udpHeader:calculateChecksum()
	-- TODO as it is mandatory for IPv6
	self.cs = 0
end

ffi.metatype("struct ipv4_header", ip4Header)
ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("union ipv6_address", ip6Addr)
ffi.metatype("struct udp_header", udpHeader)
ffi.metatype("struct rte_mbuf", pkt)


