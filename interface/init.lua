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

package.path = package.path .. ";interface/?.lua;interface/?/init.lua"
local crawl = require "configcrawl"
local parse = require "flowparse"

-- luacheck: globals configure master loadSlave statsSlave receiveSlave timestampSlave
configure = require "cli"

local function _cbr_to_delay(cbr, psize)
	-- cbr      => mbit/s        => bit/1000ns
	-- psize    => b/p           => 8bit/p
	return 8000 * psize / cbr -- => ns/p
end

local _uid_length = 16
local function _generate_uid()
	local result = {}
	for i = 1, _uid_length do
		result[i] = string.format("%x", math.random(0, 15))
	end
	return table.concat(result)
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
		local name, devs, opts = parse(arg, devnum)
		local f

		if #devs < 2 then
			log:error("Need to pass tx and rx device to this type of flow.")
		else
			f = crawl.getFlow(name, opts, {
				uid = _generate_uid(), tx = devs[1], rx = devs[2]
			})
		end

		if f and #f.tx > 0 and #f.rx > 0 then
			f:prepare()
			log:info("Flow %s => %s", f.name, f.uid)

			for _,v in ipairs(f.tx) do
				table.insert(load_flows, crawl.cloneFlow(f, { tx_dev = v }))
				devices[v].txq = devices[v].txq + 1
			end

			for _,v in ipairs(f.rx) do
				table.insert(receive_flows, crawl.cloneFlow(f, { rx_dev = v }))
				devices[v].rxq = devices[v].rxq + 1
			end

			if f.ts then
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

	if #load_flows == 0 then -- checking load_flows is enough (see above)
		log:error("No valid flows remaining.")
		return
	end

	for i,v in pairs(devices) do
		if v.txq == 0 then v.txq = 1 end
		if v.rxq == 0 then v.rxq = 1 end
		v.dev = device.config{ port = i, rxQueues = v.rxq, txQueues = v.txq }
	end
	device.waitForLinks()

	local statsPipe = pipe:newSlowPipe()

	for _,flow in ipairs(receive_flows) do
		local rxDev = devices[flow.rx_dev]
		local rxQueue = rxDev.dev:getRxQueue(rxDev.rxqi)
		rxDev.rxqi = rxDev.rxqi + 1

		local endDelay = 1000
		if flow.cbr then
			endDelay = _cbr_to_delay(flow.cbr, flow:getPacketLength(true)) * 64
		end

		mg.startTask("receiveSlave", flow, rxQueue, statsPipe, endDelay)
	end

	mg.startSharedTask("statsSlave", statsPipe)


	for _,flow in ipairs(load_flows) do
		local txDev = devices[flow.tx_dev]

		local statsQueue = txDev.dev:getTxQueue(txDev.txqi)
		local txQueue = statsQueue
		txDev.txqi = txDev.txqi + 1

		-- setup rate limit
		if flow.cbr then
			if flow.rpattern == "cbr" then
				local rc = dpdkc.rte_eth_set_queue_rate_limit(txQueue.id, txQueue.qid, flow.cbr)
				if rc ~= 0 then -- fallback to software ratelimiting
					txQueue = limiter:new(txQueue, "cbr", _cbr_to_delay(flow.cbr, flow:getPacketLength(true)))
				end
			elseif flow.rpattern == "poisson" then
				txQueue = limiter:new(txQueue, "poisson", _cbr_to_delay(flow.cbr, flow:getPacketLength(true)))
			end
		end

		mg.startTask("loadSlave", crawl.passFlow(flow), txQueue, statsQueue)
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

function loadSlave(flow, sendQueue, statsQueue)
	flow = crawl.receiveFlow(flow)

	-- TODO arp ?
	local getPacket = packet["get" .. flow.packet.proto .. "Packet"]
	local mempool = memory.createMemPool(function(buf)
		getPacket(buf):fill(flow.packet.fillTbl)
	end)

	local bufs = mempool:bufArray()
	local txCtr = stats:newDevTxCounter(flow.uid, statsQueue, "plain")

	-- dataLimit in packets, timeLimit in seconds
	local data, runtime = flow.dlim, nil
	if flow.tlim then
		runtime = timer:new(flow.tlim)
	end

	local dv = flow.packet.dynvars
	while mg.running() and (not runtime or runtime:running()) do
		bufs:alloc(flow:getPacketLength())

		if flow.updatePacket then
			for _, buf in ipairs(bufs) do
				flow.updatePacket(dv, getPacket(buf))
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
		txCtr:update()
	end

	if sendQueue.stop then
		sendQueue:stop()
	end
	txCtr:finalize()
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

	statsPipe:send{ flow.uid, "start" }

	while mg.running() and (not runtime or runtime:running()) do
		local rx = rxQueue:recv(bufs)
		for i = 1, rx do
			local buf = bufs[i]

			-- TODO packet uid recognition

			pkts = pkts + 1
			bytes = bytes + buf.pkt_len + 4
		end

		if pkts > 0 then
			statsPipe:send{ flow.uid, pkts, bytes }
		end
		pkts, bytes = 0, 0
		bufs:freeAll()

		-- TODO fix limit based stops
		--[[if not runtime and (stop_ns or 1) < 1 then
			print(delay)
			runtime = timer:new(delay / 1000)
		end]]
	end

	statsPipe:send{ flow.uid, "stop" }
	-- TODO: check the queue's overflow counter to detect lost packets
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
	while mg.running() do
		for i,v in ipairs(flows) do
			hists[i]:update(timeStampers[i]:measureLatency(v:getPacketLength(), function(buf)
				local pkt = getPacket[i](buf)
				pkt:fill(v.packet.fillTbl)
				v.updatePacket(v.packet.dynvars, pkt)
			end))
		end
		rateLimit:wait()
		rateLimit:reset()
	end

	for i,v in ipairs(flows) do
		hists[i]:save(string.format("%s/%s-%d-%d.csv", directory, v.uid, v.txqi, v.rxqi))
	end
end
