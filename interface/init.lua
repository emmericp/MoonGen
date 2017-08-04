local mg      = require "moongen"
local memory  = require "memory"
local device  = require "device"
local dpdkc   = require "dpdkc"
local limiter = require "ratelimiter"
local packet  = require "packet"
local stats   = require "stats"
local log     = require "log"

package.path = package.path .. ";interface/?.lua;interface/?/init.lua"
local crawl = require "configcrawl"

-- luacheck: globals configure master loadSlave

function configure(parser)
	parser:description("Configuration based interface for MoonGen.")
	parser:option("-c --config", "Config file directory."):default("flows")
	parser:argument("flows", "List of flow names."):args "+"
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

	local flows = {}
	for _,fname in ipairs(args.flows) do
		local f = crawl.getFlow(fname)

		if f then
			table.insert(flows, f)

			-- less error-prone way of hardcoding all four assignments
			for a in string.gmatch("txrx", "..") do
				for b in string.gmatch("txqrxq", "...") do
					local dev = devices[f[a]]
					dev[b] = dev[b] + f[a .. "_" .. b]
				end
			end
		end
	end

	if #flows == 0 then
		log:error("No valid flows remaining.")
		return
	end

	for i,v in pairs(devices) do
		v.dev = device.config{ port = i, rxQueues = v.rxq, txQueues = v.txq }
	end
	device.waitForLinks()

	-- TODO rate limits & other options
	for _,f in ipairs(flows) do
		local txDev = devices[f.tx]
		local rxDev = devices[f.rx]

		mg.startTask("loadSlave", txDev.dev:getTxQueue(txDev.txqi), rxDev.dev, crawl.passFlow(f))
		txDev.txqi = txDev.txqi + 1
	end

	mg.waitForTasks()
end

function loadSlave(txQueue, rxDev, flow)
	flow = crawl.receiveFlow(flow)

	local sendQueue = txQueue
	if flow.cbr then
		-- NOTE need to use directly to get rc, maybe change in device.lua
		local rc = dpdkc.rte_eth_set_queue_rate_limit(txQueue.id, txQueue.qid, flow.cbr)
		if rc ~= 0 then -- fallback to software ratelimiting
			sendQueue = limiter.new(txQueue, "cbr", flow.cbr)
		end
	end

	-- TODO arp ?
	local getPacket = packet["get" .. flow.packet.proto .. "Packet"]
	local mempool = memory.createMemPool(function(buf)
		getPacket(buf):fill(flow.packet.fillTbl)
	end)

	local bufs = mempool:bufArray()
	local txCtr = stats:newDevTxCounter(txQueue, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")

	while mg.running() do
		bufs:alloc(flow:getPacketLength())

		if flow.updatePacket then
			for _, buf in ipairs(bufs) do
				flow:updatePacket(getPacket(buf))
			end
		end

		bufs:offloadUdpChecksums()
		sendQueue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end

	txCtr:finalize()
	rxCtr:finalize()
end
