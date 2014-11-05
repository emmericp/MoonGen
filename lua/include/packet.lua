local ffi = require "ffi"

require "utils"
require "headers"
require "dpdkc"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bwswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift

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

function ip6Addr:get()
	--TODO
end

function ip6Addr:set(ip)
	--TODO 
end

function parseIP6Address(ip)
	local bytes = {}
	-- TODO: better parsing (shortened addresses)
	bytes = {string.match(ip, '(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x)')}

	if bytes == nil then
		return
	end
	for i = 1, 16 do
		if bytes[i] == nil then
			return 
		end
		bytes[i] = tonumber(bytes[i], 16)
	end
	--bytes = tonumberall(bytes, 16)
	
	--TODO 
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


