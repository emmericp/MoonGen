local mg         = require "moongen"
local device     = require "device"
local pipe       = require "pipe"
local log        = require "log"

package.path = package.path .. ";interface/?.lua;interface/?/init.lua"
local Flow = require "flow"
local parse = require "flowparse"
local counter = require "counter"

local loadThread = require "threads.load"
local statsThread = require "threads.stats"
local deviceStatsThread = require "threads.deviceStats"
local countThread = require "threads.count"
local timestampThread = require "threads.timestamp"


configure = require "cli" -- luacheck: globals configure

local devicesClass = {}

function devicesClass:reserveTx(tx)
	self[tx].txq = self[tx].txq + 1
end

function devicesClass:reserveRx(rx)
	self[rx].rxq = self[rx].rxq + 1
end

local function _inc(tbl, key)
	local result = tbl[key]
	tbl[key] = result + 1
	return result
end

function devicesClass:txQueue(tx)
	return self[tx].dev:getTxQueue(_inc(self[tx], "txqi"))
end

function devicesClass:rxQueue(rx)
	return self[rx].dev:getRxQueue(_inc(self[rx], "rxqi"))
end

function master(args) -- luacheck: globals master
	Flow.crawlDirectory(args.config)

	-- auto-filling device index
	local devices = setmetatable({}, {
		__index = function(tbl, key)
			if type(key) ~= "number" then
				return devicesClass[key]
			end
			local r = { rxq = 0, txq = 0, rxqi = 0, txqi = 0 }
			tbl[key] = r; return r
		end
	})

	local devnum = device.numDevices()
	local flows = {}
	for _,arg in ipairs(args.flows) do
		local fparse = parse(arg, devnum)
		-- TODO fparse.file, fparse.overwrites
		local f

		if #fparse.tx == 0 and #fparse.rx == 0 then
			log:error("Need to pass at least one tx or rx device.")
		else
			f = Flow.getInstance(fparse.name, fparse.file, fparse.options, fparse.overwrites, {
				counter = counter.new(),
				tx = fparse.tx, rx = fparse.rx
			})
		end

		if f then
			table.insert(flows, f)
			log:info("Flow %s => %s", f.proto.name, f:option "uid")
		end
	end

	loadThread.prepare(flows, devices)
	countThread.prepare(flows, devices)
	statsThread.prepare(flows, devices)
	deviceStatsThread.prepare(flows, devices)
	timestampThread.prepare(flows, devices)

	if #loadThread.flows == 0 then--and #countThread.flows == 0 then
		log:error("No valid flows remaining.")
		return
	end

	for i,v in pairs(devices) do
		local txq, rxq = v.txq, v.rxq
		txq, rxq = (txq == 0) and 1 or txq, (rxq == 0) and 1 or rxq
		v.dev = device.config{ port = i, rxQueues = rxq, txQueues = txq }
	end
	device.waitForLinks()

	local statsPipe = pipe:newSlowPipe()

	deviceStatsThread.start(devices)
	statsThread.start(devices, statsPipe)
	countThread.start(devices, statsPipe)
	loadThread.start(devices)
	timestampThread.start(devices, args.output)

	mg.waitForTasks()
end
