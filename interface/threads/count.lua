local memory  = require "memory"
local mg      = require "moongen"
local timer   = require "timer"

local crawl  = require "configcrawl"

local thread = { flows = {} }

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		for _,rx in ipairs(flow.rx) do
			table.insert(thread.flows, crawl.cloneFlow(flow, { rx_dev = rx }))
			devices:reserveRx(rx)
		end
	end
end

function thread.start(devices, pipe)
	for _,flow in ipairs(thread.flows) do
		local endDelay = 1000
		if flow.results.rate then
			endDelay = flow:getDelay() * 70 -- 64 packets per buffer + margin
		end

		mg.startTask("__INTERFACE_COUNT", crawl.passFlow(flow),
			devices:rxQueue(flow.rx_dev), pipe, endDelay)
	end
end

local function countThread(flow, rxQueue, statsPipe, delay)
	local bufs = memory.bufArray()
	local pkts, bytes = 0, 0
	local runtime

	statsPipe:send{ flow.results.uid, "start" }

	while mg.running(delay) and (not runtime or not runtime:running()) do
		local rx = rxQueue:recv(bufs)
		local uid
		for i = 1, rx do
			local buf = bufs[i]

			-- TODO packet uid recognition

			pkts = pkts + 1
			bytes = bytes + buf.pkt_len + 4
		end

		if pkts > 0 then
			statsPipe:send{ flow.results.uid, pkts, bytes }
		end
		pkts, bytes = 0, 0
		bufs:freeAll()

		if not runtime and flow.counter:isZero() then
			runtime = timer:new(delay / 1000)
		end
	end

	statsPipe:send{ flow.results.uid, "stop" }
	-- TODO check the queue's overflow counter to detect lost packets
end

__INTERFACE_COUNT = countThread -- luacheck: globals __INTERFACE_COUNT
return thread
