local mod = {}

local dpdk		= require "dpdk"
local device	= require "device"

function mod.average(data)
	local sum = 0
	for i, v in ipairs(data) do
		sum = sum + v
	end
	return sum / #data
end

function mod.median(data)
	return mod.percentile(data, 50)
end

function mod.percentile(data, p)
	local sortedData = { }
	for k, v in ipairs(data) do
		sortedData[k] = v
	end
	table.sort(sortedData)
	return data[math.ceil(#data * p / 100)]
end

function mod.stdDev(data)
	local avg = mod.average(data)
	local sum = 0
	for i, v in ipairs(data) do
		sum = sum + (v - avg) ^ 2
	end
	return (sum / (#data - 1)) ^ 0.5
end

function mod.addStats(data, ignoreFirstAndLast)
	local copy = { }
	for i = 2, #data - 1 do
		copy[i - 1] = data[i]
	end
	data.avg = mod.average(copy)
	data.stdDev = mod.stdDev(copy)
	data.median = mod.median(copy)
end

local function getPlainUpdate(direction)
	return function(stats, file, total, mpps, mbit, wireMbit)
		file:write(("%s %s %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate.\n"):format(stats.dev, direction, total, mpps, mbit, wireMbit))
		file:flush()
	end
end

local function getPlainFinal(direction)
	return function(stats, file)
		file:write(("%s %s %d packets with %d bytes payload (including CRC).\n"):format(stats.dev, direction, stats.total, stats.totalBytes))
		file:write(("%s %s %f (StdDev %f) Mpps, %f (StdDev %f) MBit/s, %f (StdDev %f) MBit/s wire rate on average.\n"):format(
			stats.dev, direction,
			stats.mpps.avg, stats.mpps.stdDev,
			stats.mbit.avg, stats.mbit.stdDev,
			stats.wireMbit.avg, stats.wireMbit.stdDev
		))
		file:flush()
	end
end

local formatters = {}
formatters["plain"] = {
	rxStatsInit = function() end, -- nothing for plain, machine-readable formats can print a header here
	rxStatsUpdate = getPlainUpdate("Received"),
	rxStatsFinal = getPlainFinal("Received"),

	txStatsInit = function() end,
	txStatsUpdate = getPlainUpdate("Sent"),
	txStatsFinal = getPlainFinal("Sent"),
}

formatters["CSV"] = formatters["plain"] -- TODO

-- base 'class' for rx and tx counters
local function newCounter(dev, pktSize, format, file)
	if type(dev) == "table" then
		-- case 1: (device, format, file)
		return newCounter(dev, nil, pktSize, format)
	end -- else: (description, size, format, file)
	if type(dev) == "table" and dev.qid then
		-- device is a queue, use the queue's device instead
		-- TODO: per-queue statistics (tricky as the abstraction in DPDK sucks)
		dev = dev.dev
	end
	file = file or io.stdout
	local closeFile = false
	if type(file) == "string" then
		file = io.open("w+")
		closeFile = true
	end
	format = format or "CSV"
	if not formatters[format] then
		error("unsupported output format " .. format)
	end
	return {
		dev = dev,
		pktSize = pktSize,
		format = format or "CSV",
		file = file,
		closeFile = closeFile,
		total = 0,
		totalBytes = 0,
		manualPkts = 0,
		mpps = {},
		mbit = {},
		wireMbit = {},
	}, type(dev) ~= "table"
end

local function printStats(self, statsType, event, ...)
	local func = formatters[self.format][statsType .. event]
	if func then
		func(self, self.file, ...)
	else
		print("[Missing formatter for " .. self.format .. "]", self.dev, statsType, event, ...)
	end
end

local function updateCounter(self, time, pkts, bytes)
	if not self.lastUpdate then
		-- very first call, save current stats but do not print anything
		self.total, self.totalBytes = pkts, bytes
		self.lastTotal = self.total
		self.lastTotalBytes = self.totalBytes
		self.lastUpdate = time
		self:print("Init")
		return
	end
	local elapsed = time - self.lastUpdate
	self.lastUpdate = time
	self.total = self.total + pkts
	self.totalBytes = self.totalBytes + bytes
	local mpps = (self.total - self.lastTotal) / elapsed / 10^6
	local mbit = (self.totalBytes - self.lastTotalBytes) / elapsed / 10^6 * 8
	local wireRate = mbit + (mpps * 20 * 8)
	self:print("Update", self.total, mpps, mbit, wireRate)
	table.insert(self.mpps, mpps)
	table.insert(self.mbit, mbit)
	table.insert(self.wireMbit, wireRate)
	self.lastTotal = self.total
	self.lastTotalBytes = self.totalBytes
end

local function finalizeCounter(self)
	mod.addStats(self.mpps, true)
	mod.addStats(self.mbit, true)
	mod.addStats(self.wireMbit, true)
	self:print("Final")
	if self.closeFile then
		self.file:close()
	end
end


local rxCounter = {}
rxCounter.__index = rxCounter

--- Create a new rx counter
-- @param dev the device to track
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newRxCounter(...)
	local obj, isManual = newCounter(...)
	if isManual then
		obj.update = rxCounter.updateManual
	end
	return setmetatable(obj, rxCounter)
end

function rxCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.dev:getRxStats()
	updateCounter(self, time, pkts, bytes)
end

function rxCounter:updateManual(pkts)
	self.manualPkts = self.manualPkts + pkts
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.manualPkts, self.manualPkts * (self.pktSize + 4)
	updateCounter(self, time, pkts, bytes)
end

function rxCounter:print(event, ...)
	printStats(self, "rxStats", event, ...)
end

function rxCounter:finalize()
	finalizeCounter(self)
end

local txCounter = {}
txCounter.__index = txCounter

--- Create a new rx counter
-- FIXME: this is slightly off when using queue:sendWithDelay() (error seems to be below 0.5%)
-- @param dev the device to track
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the file to write to, defaults to standard out
function mod:newTxCounter(...)
	local obj, isManual = newCounter(...)
	if isManual then
		obj.update = txCounter.updateManual
	end
	return setmetatable(obj, txCounter)
end


function txCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.dev:getTxStats()
	updateCounter(self, time, pkts, bytes)
end

function txCounter:updateManual(pkts)
	self.manualPkts = self.manualPkts + pkts
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.manualPkts, self.manualPkts * (self.pktSize + 4)
	self.manualPkts = 0
	updateCounter(self, time, pkts, bytes)
end

function txCounter:print(event, ...)
	printStats(self, "txStats", event, ...)
end

function txCounter:finalize()
	finalizeCounter(self)
end


return mod

