local mod = {}

local ffi	= require "ffi"
local stp	= require "StackTracePlus"

ffi.cdef [[
	struct lock { };

	struct lock* make_lock();
	void lock_lock(struct lock* lock);
	void lock_unlock(struct lock* lock);
	uint32_t lock_try_lock(struct lock* lock);
	uint32_t lock_try_lock_for(struct lock* lock, uint32_t us);
]]

local C = ffi.C

local lock = {}
lock.__index = lock

function mod:new()
	return C.make_lock()
end

function lock:lock()
	C.lock_lock(self)
end

function lock:unlock()
	C.lock_unlock(self)
end

--- Try to acquire the lock, blocking for max <timeout> microseconds.
-- This function does not block if timeout is <= 0.
-- This function may fail spuriously, i.e. return early or fail to acquire the lock.
-- @param timeout max time to wait in us
-- @returns true if the lock was acquired, false otherwise
function lock:tryLock(timeout)
	return C.lock_try_lock_for(self, timeout) == 1
end

--- Wrap a function call in lock/unlock calls.
-- Calling this is equivalent to the following pseudo-code:
--   lock:lock()
--   try {
--     func(...)
--   } finally {
--     lock:unlock()
--   }
-- @param func the function to call
-- @param ... arguments passed to the function
function lock:__call(func, ...)
	self:lock()
	local ok, err = xpcall(func, function(err)
		return stp.stacktrace(err)
	end, ...)
	self:unlock()
	if not ok then
		-- FIXME: this output is going to be ugly because it will output the local err as well :>
		error("caught error in lock-wrapped call, inner error: " .. err, 2)
	end
end

ffi.metatype("struct lock", lock)

return mod

