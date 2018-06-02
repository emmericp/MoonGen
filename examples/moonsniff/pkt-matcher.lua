--- This file holds a function which should be customized to serve your needs for packet matching

local lm        = require "libmoon"
local memory    = require "memory"
local log       = require "log"
local dpdk      = require "dpdk"
local pcap      = require "pcap"

local ffi    = require "ffi"
local C = ffi.C

local MS_TYPE = 0b01010101

return function(mbuf, scratchpad, size)
	local filled = 0 -- the number of bytes filled in the scratchpad

	pkt = mbuf:getUdpPacket()

	if pkt.payload.uint8[4] == MS_TYPE then
		ffi.copy(scratchpad, pkt.payload.uint8, 4)
		filled = 4
	end

	-- make sure we did not overfill the scratchpad
	if filled > size then log:err("UDF exceeded scratchpad size!") end

	return filled
end
