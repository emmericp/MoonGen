local dpdk	= require "dpdk"
local lock	= require "lock"

local function tryLock(l, us)
	return dpdk.launchLua("tryLockSlave", l, us or 0):wait()
end

function master()
	local l = lock:new()
	local locked, time
	l:lock()
	locked = tryLock(l)
	assert(not locked)
	locked, time = tryLock(l, 100 * 1000)
	assert(not locked)
	--assert(time >= 0.1) -- TODO: broken with gcc-4.8 (works with 4.7 and clang)
	l:unlock()
	locked = tryLock(l)
	assert(locked)
	l(function(a, b, c)
		assert(a == 1 and b == 2 and c == 3)
		local locked = tryLock(l)
		assert(not locked)
	end, 1, 2, 3)
	assert(tryLock(l))
	local ok, err = pcall(l, function()
		error("fail")
	end)
	assert(not ok)
	-- lock should be unlocked even if the wrapped function throws
	assert(tryLock(l))
end


function tryLockSlave(l, us)
	local start = dpdk.getTime()
	local locked = l:tryLock(us)
	if locked then
		l:unlock()
	end
	return locked, dpdk.getTime() -  start
end
