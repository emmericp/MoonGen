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
	if ignoreFirstAndLast then
		for i = 2, #data - 1 do
			copy[i - 1] = data[i]
		end
	else
		for i = 1, #data do
			copy[i] = data[i]
		end
	end
	data.avg = mod.average(copy)
	data.stdDev = mod.stdDev(copy)
	data.median = mod.median(copy)
end

local function getPlainUpdate(direction)
	return function(stats, file, total, mpps, mbit, wireMbit)
		file:write(("[%s] %s %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate.\n"):format(stats.name, direction, total, mpps, mbit, wireMbit))
		file:flush()
	end
end

local function getPlainFinal(direction)
	return function(stats, file)
		file:write(("[%s] %s %d packets with %d bytes payload (including CRC).\n"):format(stats.name, direction, stats.total, stats.totalBytes))
		file:write(("[%s] %s %f (StdDev %f) Mpps, %f (StdDev %f) MBit/s, %f (StdDev %f) MBit/s wire rate on average.\n"):format(
			stats.name, direction,
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

-- base constructor for rx and tx counters
local function newCounter(ctrType, name, dev, format, file)
	format = format or "CSV"
	file = file or io.stdout
	local closeFile = false
	if type(file) == "string" then
		file = io.open("w+")
		closeFile = true
	end
	if not formatters[format] then
		error("unsupported output format " .. format)
	end
	return {
		name = name,
		dev = dev,
		format = format,
		file = file,
		closeFile = closeFile,
		total = 0,
		totalBytes = 0,
		current = 0,
		currentBytes = 0,
		mpps = {},
		mbit = {},
		wireMbit = {},
	}
end

-- base class for rx and tx counters

local function printStats(self, statsType, event, ...)
	local func = formatters[self.format][statsType .. event]
	if func then
		func(self, self.file, ...)
	else
		print("[Missing formatter for " .. self.format .. "]", self.name, statsType, event, ...)
	end
end

local function updateCounter(self, time, pkts, bytes)
	if not self.lastUpdate then
		-- first call, save current stats but do not print anything
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


local rxCounter = {} -- base 'class' (not actually a class, though)
local devRxCounter = {}
local pktRxCounter = {}
local manualRxCounter = {}
devRxCounter.__index = devRxCounter
pktRxCounter.__index = pktRxCounter
manualRxCounter.__index = manualRxCounter

--- Create a new rx counter using device statistics registers.
-- @param name the name of the counter, included in the output. defaults to the device name
-- @param dev the device to track
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newDevRxCounter(name, dev, format, file)
	if type(name) == "table" then
		return self:newDevRxCounter(nil, name, dev, format)
	end
	name = name or tostring(dev):sub(2, -2) -- strip brackets as they are added by the 'plain' output again
	local obj = newCounter("dev", name, dev, format, file)
	return setmetatable(obj, devRxCounter)
end

--- Create a new rx counter that can be updated by passing packet buffers to it.
-- @param name the name of the counter, included in the output
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newPktRxCounter(name, format, file)
	local obj = newCounter("pkt", name, nil, format, file)
	return setmetatable(obj, pktRxCounter)
end

--- Create a new rx counter that has to be updated manually.
-- @param name the name of the counter, included in the output
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newManualRxCounter(name, format, file)
	local obj = newCounter("manual", name, nil, format, file)
	return setmetatable(obj, manualRxCounter)
end

-- 'Base class' (the counters are not actually derived from it, though)
function rxCounter:finalize()
	finalizeCounter(self)
end

function rxCounter:print(event, ...)
	printStats(self, "rxStats", event, ...)
end

-- Device-based counter
function devRxCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.dev:getRxStats()
	updateCounter(self, time, pkts, bytes)
end

devRxCounter.print = rxCounter.print
devRxCounter.finalize = rxCounter.finalize

-- Packet-based counter
function pktRxCounter:countPacket(buf)
	self.current = self.current + 1
	self.currentBytes = self.currentBytes + buf.pkt.pkt_len + 4 -- include CRC
end

function pktRxCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.current, self.currentBytes
	self.current, self.currentBytes = 0, 0
	updateCounter(self, time, pkts, bytes)
end

pktRxCounter.print = rxCounter.print
pktRxCounter.finalize = rxCounter.finalize


-- Manual rx counter
function manualRxCounter:update(pkts, bytes)
	self.current = self.current + pkts
	self.currentBytes = self.currentBytes + bytes
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.current, self.currentBytes
	self.current, self.currentBytes = 0, 0
	updateCounter(self, time, pkts, bytes)
end

function manualRxCounter:updateWithSize(pkts, size)
	self.current = self.current + pkts
	self.currentBytes = self.currentBytes + pkts * (size + 4)
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.current, self.currentBytes
	self.current, self.currentBytes = 0, 0
	updateCounter(self, time, pkts, bytes)
end

manualRxCounter.print = rxCounter.print
manualRxCounter.finalize = rxCounter.finalize


local txCounter = {} -- base 'class' (not actually a class, though)
local devTxCounter = {}
local pktTxCounter = {}
local manualTxCounter = {}
devTxCounter.__index = devTxCounter
pktTxCounter.__index = pktTxCounter
manualTxCounter.__index = manualTxCounter

--- Create a new tx counter using device statistics registers.
-- FIXME: this is slightly off when using queue:sendWithDelay() (error seems to be below 0.5%)
-- @param name the name of the counter, included in the output. defaults to the device name
-- @param dev the device to track
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newDevTxCounter(name, dev, format, file)
	if type(name) == "table" then
		return self:newDevTxCounter(nil, name, dev, format)
	end
	name = name or tostring(dev):sub(2, -2) -- strip brackets as they are added by the 'plain' output again
	local obj = newCounter("dev", name, dev, format, file)
	return setmetatable(obj, devTxCounter)
end

--- Create a new tx counter that can be updated by passing packet buffers to it.
-- @param name the name of the counter, included in the output
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newPktTxCounter(name, format, file)
	local obj = newCounter("pkt", name, nil, format, file)
	return setmetatable(obj, pktTxCounter)
end

--- Create a new tx counter that has to be updated manually.
-- @param name the name of the counter, included in the output
-- @param format the output format, "CSV" (default) and "plain" are currently supported
-- @param file the output file, defaults to standard out
function mod:newManualTxCounter(name, format, file)
	local obj = newCounter("manual", name, nil, format, file)
	return setmetatable(obj, manualTxCounter)
end

-- 'Base class' (the counters are not actually derived from it, though)
function txCounter:finalize()
	finalizeCounter(self)
end

function txCounter:print(event, ...)
	printStats(self, "txStats", event, ...)
end

-- Device-based counter
function devTxCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.dev:getTxStats()
	updateCounter(self, time, pkts, bytes)
end

devTxCounter.print = txCounter.print
devTxCounter.finalize = txCounter.finalize

-- Packet-based counter
function pktTxCounter:countPacket(buf)
	self.current = self.current + 1
	self.currentBytes = self.currentBytes + buf.pkt.pkt_len + 4 -- include CRC
end

function pktTxCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.current, self.currentBytes
	self.current, self.currentBytes = 0, 0
	updateCounter(self, time, pkts, bytes)
end

pktTxCounter.print = txCounter.print
pktTxCounter.finalize = txCounter.finalize


-- Manual rx counter
function manualTxCounter:update(pkts, bytes)
	self.current = self.current + pkts
	self.currentBytes = self.currentBytes + bytes
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.current, self.currentBytes
	self.current, self.currentBytes = 0, 0
	updateCounter(self, time, pkts, bytes)
end

function manualTxCounter:updateWithSize(pkts, size)
	self.current = self.current + pkts
	self.currentBytes = self.currentBytes + pkts * (size + 4)
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	local pkts, bytes = self.current, self.currentBytes
	self.current, self.currentBytes = 0, 0
	updateCounter(self, time, pkts, bytes)
end

manualTxCounter.print = txCounter.print
manualTxCounter.finalize = txCounter.finalize



return mod

