local ffi     = require "ffi"
local pipe    = require "pipe"
local mg      = require "moongen"
local serpent = require "Serpent"
local memory  = require "memory"
local log     = require "log"

local C = ffi.C

ffi.cdef[[
	struct rate_limiter_batch {
		int32_t size;
		void* bufs[0];
	};

	struct limiter_control {
		uint64_t count;
		uint64_t stop;
	};

	void mg_rate_limiter_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t link_speed, struct limiter_control* ctl);
	void mg_rate_limiter_cbr_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, struct limiter_control* ctl);
	void mg_rate_limiter_poisson_main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, uint32_t link_speed, struct limiter_control* ctl);
]]

local mod = {}
local rateLimiter = {}
mod.rateLimiter = rateLimiter

rateLimiter.__index = rateLimiter

function rateLimiter:send(bufs)
	repeat
		if pipe:sendToPacketRing(self.ring, bufs) then
			break
		end
	until not mg.running()
end

function rateLimiter:sendN(bufs, n)
	repeat
		if pipe:sendToPacketRing(self.ring, bufs, n) then
			break
		end
	until not mg.running()
end

-- stop a rate limiter thread
-- you must not continue to use a stopped rate limiter
function rateLimiter:stop()
	self.ctl.stop = 1
	memory.fence()
end

function rateLimiter:__serialize()
	return "require 'software-ratecontrol'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('software-ratecontrol').rateLimiter"), true
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
		queue = queue,
		ctl = memory.alloc("struct limiter_control*", ffi.sizeof("struct limiter_control"))
	}, rateLimiter)
	ffi.fill(obj.ctl, ffi.sizeof("struct limiter_control"))
	mg.startTask("__MG_RATE_LIMITER_MAIN", obj.ring, queue.id, queue.qid, mode, delay, queue.dev:getLinkStatus().speed, obj.ctl)
	return obj
end


function __MG_RATE_LIMITER_MAIN(ring, devId, qid, mode, delay, speed, ctl)
	if mode == "cbr" then
		C.mg_rate_limiter_cbr_main_loop(ring, devId, qid, delay, ctl)
	elseif mode == "poisson" then
		C.mg_rate_limiter_poisson_main_loop(ring, devId, qid, delay, speed, ctl)
	else
		C.mg_rate_limiter_main_loop(ring, devId, qid, speed, ctl)
	end
end

return mod
