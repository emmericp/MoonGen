local dpdkc   = require "dpdkc"
local limiter = require "software-ratecontrol"
local memory  = require "memory"
local mg      = require "moongen"
local timer   = require "timer"


local crawl  = require "configcrawl"

local thread = { flows = {} }

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		for _,tx in ipairs(flow.tx) do
			table.insert(thread.flows, crawl.cloneFlow(flow, { tx_dev = tx }))
			devices:reserveTx(tx)
		end
	end
end

function thread.start(devices)
	for _,flow in ipairs(thread.flows) do
		local txQueue = devices:txQueue(flow.tx_dev)

		-- setup rate limit
		if flow.results.rate then
			if flow.results.ratePattern == "cbr" then
				local rc = dpdkc.rte_eth_set_queue_rate_limit(txQueue.id, txQueue.qid, flow.results.rate)
				if rc ~= 0 then -- fallback to software ratelimiting
					txQueue = limiter:new(txQueue, "cbr", flow:getDelay())
				end
			elseif flow.results.ratePattern == "poisson" then
				txQueue = limiter:new(txQueue, "poisson", flow:getDelay())
			end
		end

		mg.startTask("__INTERFACE_LOAD", crawl.passFlow(flow), txQueue)
	end
end

local function loadThread(flow, sendQueue)
	flow = crawl.receiveFlow(flow)

	-- TODO arp ?
	local getPacket, hasPayload = flow.packet.getPacket, flow.packet.hasPayload
	local mempool = memory.createMemPool(function(buf)
		getPacket(buf):fill(flow.packet.fillTbl)
	end)

	local bufs = mempool:bufArray()

	-- dataLimit in packets, timeLimit in seconds
	local data, runtime = flow.results.dataLimit, nil
	if flow.results.timeLimit then
		runtime = timer:new(flow.results.timeLimit)
	end

	flow.lock:lock()
	flow.counter.count = flow.counter.count + 1
	flow.counter.active = 1
	flow.lock:unlock()

	local dv = flow.packet.dynvars
	local uid = flow.results.uid
	while mg.running() and (not runtime or runtime:running()) do
		bufs:alloc(flow:getPacketLength())

		if flow.updatePacket then
			if hasPayload then
				for _, buf in ipairs(bufs) do
					local pkt = getPacket(buf)
					flow.updatePacket(dv, pkt)
					pkt.payload.uint32[0] = uid
				end
			else
				for _, buf in ipairs(bufs) do
					flow.updatePacket(dv, getPacket(buf))
				end
			end
		end

		if data then
			data = data - bufs.size
			if data <= 0 then
				sendQueue:sendN(bufs, bufs.size + data)
				break
			end
		end

		bufs:offloadUdpChecksums()
		sendQueue:send(bufs)
	end

	flow.lock:lock()
	flow.counter.count = flow.counter.count - 1
	flow.lock:unlock()

	if sendQueue.stop then
		sendQueue:stop()
	end
end

__INTERFACE_LOAD = loadThread -- luacheck: globals __INTERFACE_LOAD
return thread
