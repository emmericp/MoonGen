local dpdkc   = require "dpdkc"
local limiter = require "software-ratecontrol"
local memory  = require "memory"
local mg      = require "moongen"
local timer   = require "timer"
local stats   = require "stats"

local Flow = require "flow"

local thread = { flows = {} }

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		for _,tx in ipairs(flow:property "tx") do
			table.insert(thread.flows, flow:clone{ tx_dev = tx })
			devices:reserveTx(tx)
		end
	end
end

function thread.start(devices)
	for _,flow in ipairs(thread.flows) do
		local txQueue = devices:txQueue(flow:property "tx_dev")

		-- setup rate limit
		if flow:option "rate" then
			if flow:option "ratePattern" == "cbr" then
				local rc = dpdkc.rte_eth_set_queue_rate_limit(txQueue.id, txQueue.qid, flow:option "rate")
				if rc ~= 0 then -- fallback to software ratelimiting
					txQueue = limiter:new(txQueue, "cbr", flow:getDelay())
				end
			elseif flow.results.ratePattern == "poisson" then
				txQueue = limiter:new(txQueue, "poisson", flow:getDelay())
			end
		end

		mg.startTask("__INTERFACE_LOAD", flow, txQueue)
	end
end

local function loadThread(flow, sendQueue)
	flow = Flow.restore(flow)

	local counter = stats:newPktTxCounter(
		("Flow: dev=%d uid=%#x"):format(flow:property "tx_dev", flow:option "uid")
	)

	local mempool = memory.createMemPool(function(buf) flow:fillBuf(buf) end)
	local bufs = mempool:bufArray()

	-- dataLimit in packets, timeLimit in seconds
	local data, runtime = flow:option "dataLimit", nil
	if flow:option "timeLimit" then
		runtime = timer:new(flow:option "timeLimit")
	end

	flow:property("counter"):inc()

	while mg.running() and (not runtime or runtime:running()) do
		bufs:alloc(flow:packetSize())

		if flow.isDynamic then
			for _, buf in ipairs(bufs) do
				flow:updateBuf(buf)
				counter:countPacket(buf)
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

		counter:update()
	end

	flow:property("counter"):dec()

	if sendQueue.stop then
		sendQueue:stop()
	end

	counter:finalize()
end

__INTERFACE_LOAD = loadThread -- luacheck: globals __INTERFACE_LOAD
return thread
