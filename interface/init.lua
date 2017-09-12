local mg         = require "moongen"
local memory     = require "memory"
local device     = require "device"
local dpdkc      = require "dpdkc"
local limiter    = require "software-ratecontrol"
local packet     = require "packet"
local pipe       = require "pipe"
local stats      = require "stats"
local timer      = require "timer"
local hist       = require "histogram"
local ts         = require "timestamping"
local log        = require "log"
local lock        = require "lock"
local ffi        = require "ffi"

package.path = package.path .. ";interface/?.lua;interface/?/init.lua"
local crawl = require "configcrawl"
local parse = require "flowparse"

ffi.cdef[[
	struct counter_t {
		uint8_t active;
		uint32_t count;
	};
]]
ffi.metatype("struct counter_t", {
	__index = {
		isZero = function(self)
			return self.active == 1 and self.count == 0
		end
	}
})
local function _new_counter()
	local cnt = memory.alloc("struct counter_t*", 5)
	cnt.active, cnt.count = 0, 0
	return cnt
end

-- luacheck: globals configure master loadSlave statsSlave receiveSlave timestampSlave
configure = require "cli"

local function _cbr_to_delay(cbr, psize)
	-- cbr      => mbit/s        => bit/1000ns
	-- psize    => b/p           => 8bit/p
	return 8000 * psize / cbr -- => ns/p
end

function master(args)
	crawl(args.config)

	-- auto-filling device index
	local devices = setmetatable({}, {
		__index = function(tbl, key)
			local r = { rxq = 0, txq = 0, rxqi = 0, txqi = 0 }
			tbl[key] = r; return r
		end
	})
	local devnum = device.numDevices()

	local load_flows, timestamp_flows, receive_flows = {}, {}, {}
	for _,arg in ipairs(args.flows) do
		local name, tx, rx, opts = parse(arg, devnum)
		local f

		if #tx == 0 and #rx == 0 then
			log:error("Need to pass at least one tx or rx device.")
		else
			-- TODO support for custom uid
			f = crawl.getFlow(name, opts, {
				lock = lock:new(),
				counter = _new_counter(),
				tx = tx, rx = rx
			})
		end

		if f then
			log:info("Flow %s => %s", f.name, f.results.uid)

			for _,v in ipairs(f.tx) do
				table.insert(load_flows, crawl.cloneFlow(f, { tx_dev = v }))
				devices[v].txq = devices[v].txq + 1
			end

			for _,v in ipairs(f.rx) do
				table.insert(receive_flows, crawl.cloneFlow(f, { rx_dev = v }))
				devices[v].rxq = devices[v].rxq + 1
			end

			if f.results.timestamp then
				for _,v in ipairs(f.tx) do
					table.insert(timestamp_flows, crawl.cloneFlow(f, {
						tx_dev = v, rx_dev = f.rx[1]
					}))
					devices[v].txq = devices[v].txq + 1
					devices[f.rx[1]].rxq = devices[f.rx[1]].rxq + 1
				end
			end
		end
	end

	if #load_flows == 0 and #receive_flows == 0 then
		log:error("No valid flows remaining.")
		return
	end

	local txStats, rxStats = {}, {}
	for i,v in pairs(devices) do
		local txq, rxq = v.txq, v.rxq
		txq, rxq = (txq == 0) and 1 or txq, (rxq == 0) and 1 or rxq

		v.dev = device.config{ port = i, rxQueues = rxq, txQueues = txq }

		if v.txq > 0 then
			table.insert(txStats, v.dev)
		end
		if v.rxq > 0 then
			table.insert(rxStats, v.dev)
		end
	end
	device.waitForLinks()

	-- TODO stopping stats task
	-- stats.startStatsTask{ txDevices = txStats, rxDevices = rxStats }

	local statsPipe = pipe:newSlowPipe()

	for _,flow in ipairs(receive_flows) do
		local rxDev = devices[flow.rx_dev]
		local rxQueue = rxDev.dev:getRxQueue(rxDev.rxqi)
		rxDev.rxqi = rxDev.rxqi + 1

		local endDelay = 1000
		if flow.results.rate then
			endDelay = _cbr_to_delay(flow.results.rate, flow:getPacketLength(true)) * 64
		end

		mg.startTask("receiveSlave", flow, rxQueue, statsPipe, endDelay)
	end

	mg.startSharedTask("statsSlave", statsPipe)


	for _,flow in ipairs(load_flows) do
		local txDev = devices[flow.tx_dev]

		local txQueue = txDev.dev:getTxQueue(txDev.txqi)
		txDev.txqi = txDev.txqi + 1

		-- setup rate limit
		if flow.results.rate then
			if flow.results.ratePattern == "cbr" then
				local rc = dpdkc.rte_eth_set_queue_rate_limit(txQueue.id, txQueue.qid, flow.results.rate)
				if rc ~= 0 then -- fallback to software ratelimiting
					txQueue = limiter:new(txQueue, "cbr", _cbr_to_delay(flow.results.rate, flow:getPacketLength(true)))
				end
			elseif flow.results.ratePattern == "poisson" then
				txQueue = limiter:new(txQueue, "poisson", _cbr_to_delay(flow.results.rate, flow:getPacketLength(true)))
			end
		end

		mg.startTask("loadSlave", crawl.passFlow(flow), txQueue)
	end

	for i,flow in ipairs(timestamp_flows) do
		local txDev = devices[flow.tx_dev]
		local rxDev = devices[flow.rx_dev]

		flow.txQueue = txDev.dev:getTxQueue(txDev.txqi)
		flow.txqi = txDev.txqi
		txDev.txqi = txDev.txqi + 1

		flow.rxQueue = rxDev.dev:getRxQueue(rxDev.rxqi)
		flow.rxqi = txDev.rxqi
		rxDev.rxqi = rxDev.rxqi + 1

		timestamp_flows[i] = crawl.passFlow(flow)
	end

	if #timestamp_flows >0 then
		mg.startSharedTask("timestampSlave", timestamp_flows, args.output)
	end

	mg.waitForTasks()
end

function loadSlave(flow, sendQueue)
	flow = crawl.receiveFlow(flow)

	-- TODO arp ?
	local getPacket = packet["get" .. flow.packet.proto .. "Packet"]
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
			for _, buf in ipairs(bufs) do
				local pkt = getPacket(buf)
				flow.updatePacket(dv, pkt)
				pkt.payload.uint32[0] = uid
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

local function statsSlaveRunning(numCtrs)
	if numCtrs then
		return numCtrs > 0
	end
	return mg.running()
end

function statsSlave(statsPipe)
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

function receiveSlave(flow, rxQueue, statsPipe, delay)
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

function timestampSlave(flows, directory)
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
