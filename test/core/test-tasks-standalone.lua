local dpdk		= require "dpdk"
local dpdkc		= require "dpdkc"


function master()
	for i = 1, 100 do
		for i = 1, 3 do
			dpdk.launchLua("emptyTask")
		end
		dpdk.sleepMillis(10)
		-- this will fail if there is something wrong with recycling
	end
	local task = dpdk.launchLua("passThroughTask", "string", 2, 3)
	print(task)
	print(task:wait())
end

function emptyTask()
end

function passThroughTask(...)
	return ...
end

