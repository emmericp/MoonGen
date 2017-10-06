local memory  = require "memory"
local mg      = require "moongen"
local timer   = require "timer"
local stats   = require "stats"
local packet  = require "packet"

local Flow = require "flow"

local thread = { flows = {} }

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		for _,rx in ipairs(flow:property "rx") do
			table.insert(thread.flows, flow:clone{ rx_dev = rx })
			devices:reserveRss(rx)
		end
	end
end

function thread.start(devices)
	for _,flow in ipairs(thread.flows) do
		local endDelay = 1000
		if flow:option "rate" then
			endDelay = flow:getDelay() * 70 -- 64 packets per buffer + margin
		end

		mg.startTask("__INTERFACE_COUNT", flow, devices:rssQueue(flow:property "rx_dev"), endDelay)
	end
end

local statsManager = {}
statsManager.__index = statsManager

local function getCounter(dev, uid)
	return stats:newPktRxCounter(("Flow: dev=%s uid=%s"):format(tostring(dev), tostring(uid)))
end

local function finalize(self)
	for i,v in pairs(self) do
		if type(i) == "number" then
			v:finalize()
		end
	end
end

function statsManager.new(dev)
	return setmetatable({ dev = dev, finalize = finalize }, statsManager)
end

function statsManager:__index(key)
	local cnt = getCounter(self.dev, key == 0 and "?" or key)
	self[key] = cnt
	return cnt
end

local function getPayload(pkt)
	return pkt.payload.uint32[0]
end

local function countThread(flow, rxQueue, delay)
	flow = Flow.restore(flow)

	local bufs = memory.bufArray()
	local counters = statsManager.new(rxQueue.id)
	local runtime

	while mg.running(delay) and (not runtime or not runtime:running()) do
		local rx = rxQueue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]

			local pkt = buf:get()
			local status, result = pcall(getPayload, pkt)
			local uid = status and result or 0

			counters[uid]:countPacket(buf)
			counters[uid]:update()
		end

		bufs:freeAll()
		if not runtime and flow:property("counter"):isZero() then
			runtime = timer:new(delay / 1000)
		end
	end

	counters:finalize()
	-- TODO check the queue's overflow counter to detect lost packets
end

__INTERFACE_COUNT = countThread -- luacheck: globals __INTERFACE_COUNT
return thread
