local ffi	= require "ffi"
local pipe	= require "pipe"
local dpdk	= require "dpdk"
local serpent = require "Serpent"
local memory = require "memory"
local log = require "log"
require "dpdkc"

local C = ffi.C

ffi.cdef[[
	struct rate_limiter_batch {
		int32_t size;
		void* bufs[0];
	};

	void rate_limiter_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue);
	void rate_limiter_cbr_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target);
	void rate_limiter_poisson_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, uint32_t link_speed);
]]

local mod = {}
local rateLimiter = {}
mod.rateLimiter = rateLimiter

rateLimiter.__index = rateLimiter

function rateLimiter:send(bufs)
	pipe:sendToPacketRing(self.ring, bufs)
end

function rateLimiter:__serialize()
	return "require 'ratelimiter'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('ratelimiter').rateLimiter"), true
end

--- Create a new rate limiter that allows for precise inter-packet gap generation by wrapping a tx queue.
-- By default it uses packet delay information from buf:setDelay().
-- Can only be created from the master task because it spawns a separate thread.
-- @param queue the wrapped tx queue
-- @param mode optional, either "cbr", "poisson", or "custom". Defaults to custom.
-- @param delay optional, inter-departure time in nanoseconds for cbr, 1/lambda (average) for poisson
function mod:new(queue, mode, delay)
	mode = mode or "custom"
	if mode ~= "poisson" and mode ~= "cbr" and mode ~= "custom" then
		log:fatal("Unsupported mode " .. mode)
	end
	local ring = pipe:newPacketRing()
	local obj = setmetatable({
		ring = ring.ring,
		mode = mode,
		delay = delay,
		queue = queue
	}, rateLimiter)
	dpdk.launchLua("__MG_RATE_LIMITER_MAIN", obj.ring, queue.id, queue.qid, mode, delay, queue.dev:getLinkStatus().speed)
	return obj
end


function __MG_RATE_LIMITER_MAIN(ring, devId, qid, mode, delay, speed)
	if mode == "cbr" then
		C.rate_limiter_cbr_main_loop(ring, devId, qid, delay)
	elseif mode == "poisson" then
		C.rate_limiter_poisson_main_loop(ring, devId, qid, delay, speed)
	else
		C.rate_limiter_main_loop(ring, devId, qid)
	end
end

return mod

