-- Start MoonGen and initialize all devices.

local dpdk 	= require "dpdk"
local device 	= require "device"

local tconfig 	= require "tconfig"

function master()
	local cards = tconfig.cards()
	local devs = {}
	for i=1, #cards do
		devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()
	
	slave()
end


-- Do nothing.
function slave()
end
