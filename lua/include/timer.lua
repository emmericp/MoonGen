local mod = {}

local dpdk = require "dpdk"

local timer = {}
timer.__index = timer

function mod:new(time)
	return setmetatable({
		time = time,
		stop = dpdk.getTime() + time
	}, timer)
end

function timer:running()
	return self.stop > dpdk.getTime()
end

function timer:expired()
	return self.stop <= dpdk.getTime()
end

function timer:reset()
	self.stop = dpdk.getTime() + self.time
end

--- Perform a busy wait on the timer.
-- Returns early if MoonGen is stopped (mg.running() == false).
function timer:busyWait()
	while not self:expired() and dpdk.running() do
	end
	return dpdk.running()
end

--- Perform a non-busy wait on the timer.
-- Might be less accurate than busyWait()
function timer:wait()
	-- TODO: implement
	return self:busyWait()
end

return mod

