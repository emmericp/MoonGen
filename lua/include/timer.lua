local mod = {}

local dpdk = require "dpdk"

local timer = {}
timer.__index = timer

function mod:new(time)
	return setmetatable({
		stop = dpdk.getTime() + time
	}, timer)
end

function timer:running()
	return self.stop > dpdk.getTime()
end

function timer:expired()
	return self.stop <= dpdk.getTime()
end
return mod

