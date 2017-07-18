local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local stats  = require "stats"

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

	local devices = setmetatable({}, {
		__index = function(tbl, key)
			local r = { rxq = 0, txq = 0, rxqi = 0, txqi = 0 }
			tbl[key] = r; return r
		end
	})
	local flows = {}
	for _,fname in ipairs(args.flows) do
		local f = crawl.getFlow(fname)
		table.insert(flows, f)

		local txDev = devices[f.tx]
		local rxDev = devices[f.rx]

		-- TODO figure out queue count per flow
		txDev.txq = txDev.txq + 1
		txDev.rxq = txDev.rxq + 1
		rxDev.txq = rxDev.txq + 1
		rxDev.rxq = rxDev.rxq + 1
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

	-- TODO arp ?
	local mempool = memory.createMemPool(function(buf)
		buf["get" .. flow.packet.proto .. "Packet"](buf):fill(flow.packet.fillTbl)
	end)

	local bufs = mempool:bufArray()
	local txCtr = stats:newDevTxCounter(txQueue, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")

	-- start at 0 to leave first packet unchanged
	-- would skip first values of ranges otherwise
	local dynvarIndex, dynvarSize = 0, #flow.packet.dynvars

	while mg.running() do
		bufs:alloc(flow.packet.fillTbl.pktLength)

		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			local dv = flow.packet.dynvars[dynvarIndex]

			dynvarIndex = dynvarIndex + 1
			if dynvarIndex > dynvarSize then
				dynvarIndex = 1
			end

			if dv then
				local var = pkt[dv.pkt][dv.var]
				if type(var) == "cdata" then
					var:set(dv.func())
				else
					pkt[dv.pkt][dv.var] = dv.func()
				end
			end
		end

		bufs:offloadUdpChecksums()
		txQueue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end

	txCtr:finalize()
	rxCtr:finalize()
end
