local device = require "device"
local ffi    = require "ffi"
local pkt    = require "packet"
require "dpdkc" -- struct definitions

local txQueue = device.__txQueuePrototype
local C = ffi.C
local uint64Ptr = ffi.typeof("uint64_t*")

ffi.cdef[[
	void moongen_send_packet_with_timestamp(uint8_t port_id, uint16_t queue_id, struct rte_mbuf* pkt, uint16_t offs);
]]

--- Send a single timestamped packet
-- @param bufs bufArray, only the first packet in it will be sent
-- @param offs offset in the packet at which the timestamp will be written. will be aligned to a uint64_t
function txQueue:sendWithTimestamp(bufs, offs)
	self.used = true
	offs = offs and offs / 8 or 6 -- first 8-byte aligned value in UDP payload
	C.moongen_send_packet_with_timestamp(self.id, self.qid, bufs.array[0], offs)
end

function pkt:getSoftwareTxTimestamp(offs)
	local offs = offs and offs / 8 or 6 -- default from sendWithTimestamp
	return uint64Ptr(self:getData())[offs]
end
