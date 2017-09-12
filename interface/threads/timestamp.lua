local hist   = require "histogram"
local mg     = require "moongen"
local packet = require "packet"
local timer  = require "timer"
local ts     = require "timestamping"

local crawl  = require "configcrawl"

local thread = { flows = {} }

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		if flow.results.timestamp then
			local rx = flow.rx[1]
			for _,tx in ipairs(flow.tx) do
				table.insert(thread.flows, crawl.cloneFlow(flow, {
					tx_dev = tx, rx_dev = rx
				}))
				devices:reserveTx(tx)
				devices:reserveRx(rx)
			end
		end
	end
end

function thread.start(devices, ...)
	for i,flow in ipairs(thread.flows) do
		flow.txQueue = devices:txQueue(flow.tx_dev)
		flow.rxQueue = devices:rxQueue(flow.rx_dev)

		thread.flows[i] = crawl.passFlow(flow)
	end

	if #thread.flows > 0 then
		mg.startSharedTask("__INTERFACE_TIMESTAMPING", thread.flows, ...)
	end
end

local function timestampThread(flows, directory)
	local timeStampers, getPacket, hists = {}, {}, {}

	for i,v in ipairs(flows) do
		flows[i] = crawl.receiveFlow(v)

		local isUdp = v.packet.proto == "Udp"
		timeStampers[i] = ts:newTimestamper(v.txQueue, v.rxQueue, nil, isUdp)
		getPacket[i] = packet["get" .. v.packet.proto .. "Packet"]
		hists[i] = hist()

		local minLength = isUdp and 84 or 68
		if v:getPacketLength() < minLength then
			v.psize = minLength
		end
	end

	local rateLimit = timer:new(0.001)
	local activeFlows = 1
	while mg.running() and activeFlows > 0 do
		activeFlows = 0
		for i,v in ipairs(flows) do
			if not v.counter:isZero() then
				activeFlows = activeFlows + 1
				hists[i]:update(timeStampers[i]:measureLatency(v:getPacketLength(), function(buf)
					local pkt = getPacket[i](buf)
					pkt:fill(v.packet.fillTbl)
					v.updatePacket(v.packet.dynvars, pkt)
				end))
			end
		end
		rateLimit:wait()
		rateLimit:reset()
	end

	for i,v in ipairs(flows) do
		hists[i]:save(string.format("%s/%s_%d-%d_%d.csv", directory, v.name, v.results.uid, v.txQueue.id, v.rxQueue.id))
	end
end

__INTERFACE_TIMESTAMPING = timestampThread -- luacheck: globals __INTERFACE_TIMESTAMPING
return thread
