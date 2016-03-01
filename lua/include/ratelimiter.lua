local ffi	= require "ffi"
local pipe	= require "pipe"
local dpdk	= require "dpdk"
local serpent = require "Serpent"
local memory = require "memory"
require "dpdkc"

local C = ffi.C

ffi.cdef[[
	struct rate_limiter_batch {
		int32_t size;
		void* bufs[0];
	};

	void rate_limiter_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue);
	void rate_limiter_cbr_main_loop(void* ring, uint8_t device, uint16_t queue, uint32_t target);
]]

local mod = {}
local rateLimiter = {}
mod.rateLimiter = rateLimiter

rateLimiter.__index = rateLimiter

function rateLimiter:send(bufs)
	--pipe:sendToPacketRing(self.ring, bufs)
	local batch = memory.alloc("struct rate_limiter_batch*", 16 + bufs.size * 8)
--	ffi.copy(batch.bufs, bufs.array, bufs.size * 8)
	batch.size = bufs.size
	for i = 1, bufs.size do
		batch.bufs[i - 1] = bufs.array[i - 1]
	end
	while not pipe:sendToFastPipe(self.ring, batch) do
	end
end

function rateLimiter:__serialize()
	return "require 'ratelimiter'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('ratelimiter').rateLimiter"), true
end

--- Create a new rate limiter that allows for precise inter-packet gap generation by wrapping a tx queue.
-- By default it uses packet delay information from buf:setDelay().
-- Can only be created from the master task because it spawns a separate thread.
-- @param queue the wrapped tx queue
-- @param mode optional, either "cbr" or "custom". Defaults to custom.
-- @param delay optional, inter-departure time in nanoseconds for mode == "cbr"
function mod:new(queue, mode, delay)
	if mode and mode ~= "cbr" and mode ~= "custom" then
		log:fatal("Unsupported mode " .. mode)
	end
	--local ring = pipe:newPacketRing()
	local ring = pipe:newFastPipe(32)
	local obj = setmetatable({
		ring = ring.pipe,
		mode = mode,
		delay = delay,
		queue = queue
	}, rateLimiter)
	dpdk.launchLua("__MG_RATE_LIMITER_MAIN", obj.ring, queue.id, queue.qid, mode, delay)
	return obj
end


function __MG_RATE_LIMITER_MAIN(ring, devId, qid, mode, delay)
	if mode then
		C.rate_limiter_cbr_main_loop(ring, devId, qid, delay)
	else
		C.rate_limiter_main_loop(ring, devId, qid)
	end
end

return mod

