local mg    = require "moongen"
local stats = require "stats"

local thread =  {}

function thread.prepare() end

function thread.start(_, pipe)
	mg.startSharedTask("__INTERFACE_STATS", pipe)
end


local function statsSlaveRunning(numCtrs)
	if numCtrs then
		return numCtrs > 0
	end
	return mg.running()
end

local function statsThread(statsPipe)
	local ctrs, numCtrs = {}

	while statsSlaveRunning(numCtrs) do
		local v = statsPipe:tryRecv(10)

		if v then
			if v[2] == "start" then
				if not ctrs[v[1]] then
					ctrs[v[1]] = stats:newManualRxCounter(v[1], "plain")
				end
				numCtrs = (numCtrs or 0) + 1
			elseif v[2] == "stop" then
				numCtrs = numCtrs - 1
			else
				ctrs[v[1]]:update(v[2], v[3])
			end
		end
	end

	for _,v in pairs(ctrs) do
		v:finalize()
	end
end

__INTERFACE_STATS = statsThread -- luacheck: globals __INTERFACE_STATS
return thread
