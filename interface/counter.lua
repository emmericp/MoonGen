local ffi    = require "ffi"
local memory = require "memory"
local lock   = require "lock"

local mod = {}

ffi.cdef[[
	struct counter {
		uint8_t active;
		uint32_t count;
		struct lock* lock;
	};
]]

local counter = {}
counter.__index = counter

function mod.new()
	local cnt = memory.alloc("struct counter*", ffi.sizeof("struct counter"))
	cnt.active, cnt.count, cnt.lock = 0, 0, lock:new()
	return cnt
end


function counter:isZero()
	return self.active == 1 and self.count == 0
end

function counter:inc()
	self.lock:lock()
	self.count = self.count + 1
	self.active = 1
	self.lock:unlock()
end

function counter:dec()
	self.lock:lock()
	self.count = self.count - 1
	self.lock:unlock()
end

ffi.metatype("struct counter", counter)

return mod
