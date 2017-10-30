local mg      = require "moongen"
local stats   = require "stats"

local thread = { devices = {} }

function thread.prepare(flows)
	for _,flow in ipairs(flows) do
		for _,v in ipairs{ "Tx", "Rx" } do
			for _,id in ipairs(flow:property(v:lower())) do
				table.insert(thread.devices, { v, id, flow })
			end
		end
	end
end

local function add_flow(tbl, key, flow, devices)
	local result = tbl[key]
	if not result then
		result = { dev = devices[key].dev }
		tbl[key] = result
	end
	table.insert(result, flow)
end

function thread.start(devices)
	local devs = { Tx = {}, Rx = {} }

	for _,v in ipairs(thread.devices) do
		add_flow(devs[v[1]], v[2], v[3], devices)
	end

	mg.startSharedTask("__INTERFACE_DEVICE_STATS", devs)
end

local function isActive(flows)
	for _,flow in ipairs(flows) do
		if not flow.properties.counter:isZero() then
			return true
		end
	end

	return false
end

local function deviceStatsThread(devs)
	local counters = {}

	for _,v in ipairs{ "Tx", "Rx" } do
		local getCounter = stats["newDev" .. v .. "Counter"]
		for _,flows in pairs(devs[v]) do
			table.insert(counters, { flows = flows, counter = getCounter(stats, flows.dev) })
		end
	end

	local len = #counters
	while mg.running(200) and len > 0 do
		local offset = 0

		for i = 1, len do
			local ctr = counters[i]
			local active = isActive(ctr.flows)

			if active then
				ctr.counter:update()
			end

			if not active then
				ctr.counter:finalize()
				counters[i] = nil
				offset = offset + 1
			elseif offset > 0 then
				counters[i] = nil
				counters[i - offset] = ctr
			end
		end

		len = len - offset
		mg.sleepMillisIdle(10)
	end

end

__INTERFACE_DEVICE_STATS = deviceStatsThread -- luacheck: globals __INTERFACE_DEVICE_STATS

return thread
