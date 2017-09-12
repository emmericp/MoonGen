local mg         = require "moongen"
local memory     = require "memory"
local device     = require "device"
local pipe       = require "pipe"
local log        = require "log"
local lock       = require "lock"
local ffi        = require "ffi"

package.path = package.path .. ";interface/?.lua;interface/?/init.lua"
local crawl = require "configcrawl"
local parse = require "flowparse"

local loadThread = require "threads.load"
local statsThread = require "threads.stats"
local countThread = require "threads.count"
local timestampThread = require "threads.timestamp"

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
	crawl(args.config)

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
		local name, tx, rx, opts = parse(arg, devnum)
		local f

		if #tx == 0 and #rx == 0 then
			log:error("Need to pass at least one tx or rx device.")
		else
			f = crawl.getFlow(name, opts, {
				lock = lock:new(),
				counter = _new_counter(),
				tx = tx, rx = rx
			})
		end

		if f then
			table.insert(flows, f)
			log:info("Flow %s => %s", f.name, f.results.uid)
		end
	end

	loadThread.prepare(flows, devices)
	countThread.prepare(flows, devices)
	statsThread.prepare(flows, devices)
	timestampThread.prepare(flows, devices)

	if #loadThread.flows == 0 and #countThread.flows == 0 then
		log:error("No valid flows remaining.")
		return
	end

	local txStats, rxStats = {}, {}
	for i,v in pairs(devices) do
		local txq, rxq = v.txq, v.rxq
		txq, rxq = (txq == 0) and 1 or txq, (rxq == 0) and 1 or rxq

		v.dev = device.config{ port = i, rxQueues = rxq, txQueues = txq }

		if v.txq > 0 then
			-- table.insert(txStats, v.dev)
		end
		if v.rxq > 0 then
			-- table.insert(rxStats, v.dev)
		end
	end
	device.waitForLinks()

	-- TODO stopping stats task
	-- stats.startStatsTask{ txDevices = txStats, rxDevices = rxStats }

	local statsPipe = pipe:newSlowPipe()

	statsThread.start(devices, statsPipe)
	countThread.start(devices, statsPipe)
	loadThread.start(devices)
	timestampThread.start(devices, args.output)

	mg.waitForTasks()
end
