local ffi = require "ffi"

require "utils"
require "headers"
require "dpdkc"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bwswap16

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

local udpPacketType = ffi.typeof("struct udp_packet*")

function pkt:getUDPPacket()
	return udpPacketType(self.pkt.data)
end

local ip4Addr = {}
ip4Addr.__index = ip4Addr

function ip4Addr:get()
	return bswap(self.uint32)
end

function ip4Addr:set(ip)
	self.uint32 = bswap(ip)
end

function ip4Addr:getString()
	return ("%d.%d.%d.%d"):format(self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3])
end

ffi.metatype("union ipv4_address", ip4Addr)
ffi.metatype("struct rte_mbuf", pkt)

