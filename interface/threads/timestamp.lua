local hist   = require "histogram"
local mg     = require "moongen"
local timer  = require "timer"
local ts     = require "timestamping"

local Flow  = require "flow"

local thread = { flows = {} }

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		if flow:option "timestamp" then
			local rx = flow:property("rx")[1]
			for _,tx in ipairs(flow:property "tx") do
				table.insert(thread.flows, flow:clone{ tx_dev = tx, rx_dev = rx })
				devices:reserveTx(tx)
				devices:reserveRx(rx)
			end
		end
	end
end

function thread.start(devices, ...)
	for i,flow in ipairs(thread.flows) do
		flow:setProperty("txQueue", devices:txQueue(flow:property "tx_dev"))
		flow:setProperty("rxQueue", devices:rxQueue(flow:property "rx_dev"))

		thread.flows[i] = flow
	end

	if #thread.flows > 0 then
		mg.startSharedTask("__INTERFACE_TIMESTAMPING", thread.flows, ...)
	end
end

local function timestampThread(flows, directory)
	local timeStampers, hists = {}, {}

	for i,v in ipairs(flows) do
		local flow = Flow.restore(v)
		flows[i] = flow

		local isUdp = flow.packet.proto == "Udp"
		timeStampers[i] = ts:newTimestamper(
			flow:property "txQueue", flow:property "rxQueue",
			nil, isUdp
		)
		hists[i] = hist()

		local minLength = isUdp and 84 or 68
		if flow:packetSize() < minLength then
			flow.packet.fillTbl.pktLength = minLength
		end
	end

	local rateLimit = timer:new(0.001)
	local activeFlows = 1
	while mg.running() and activeFlows > 0 do
		activeFlows = 0
		for i,flow in ipairs(flows) do
			if not flow:property("counter"):isZero() then
				activeFlows = activeFlows + 1
				hists[i]:update(timeStampers[i]:measureLatency(
					flow:packetSize(), function(buf)
						if flow.isDynamic then
							flow:fillUpdateBuf(buf)
						else
							flow:fillBuf(buf)
						end
					end
				))
			end
		end
		rateLimit:wait()
		rateLimit:reset()
	end

	for i,flow in ipairs(flows) do
		hists[i]:save(string.format("%s/%s_%d-%d_%d.csv", directory,
			flow.proto.name, flow:option "uid", flow:property("txQueue").id, flow:property("rxQueue").id))
	end
end

__INTERFACE_TIMESTAMPING = timestampThread -- luacheck: globals __INTERFACE_TIMESTAMPING
return thread
