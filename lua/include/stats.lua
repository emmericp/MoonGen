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

local formatters = {}
formatters["plain"] = {
	rxStatsInit = function(stats, file)
		-- nothing for plain, machine-readable formats can print a header here
	end,

	rxStatsUpdate = function(stats, file, total, mpps, mbit, wireMbit)
		file:write(("%s Received %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate.\n"):format(stats.dev, total, mpps, mbit, wireMbit))
		file:flush()
	end,

	rxStatsFinal = function(stats, file)
		file:write(("%s Received %d packets and %d bytes.\n"):format(stats.dev, stats.total, stats.totalBytes))
		file:write(("%s Received %f (StdDev %f) Mpps, %f (StdDev %f) MBit/s, %f (StdDev %f) MBit/s wire rate on average.\n"):format(
			stats.dev,	
			stats.mpps.avg, stats.mpps.stdDev,
			stats.mbit.avg, stats.mbit.stdDev,
			stats.wireMbit.avg, stats.wireMbit.stdDev
		))
		file:flush()
	end,
}

formatters["CSV"] = formatters["plain"] -- TODO


local rxCounter = {}
rxCounter.__index = rxCounter

--- Create a new rx counter
-- @param dev the device to track
-- @param format the output format, "CSV" (default) and "plain" are currently supported
function mod:newRxCounter(dev, format, file)
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
	return setmetatable({
		dev = dev,
		format = format or "CSV",
		file = file,
		closeFile = closeFile,
		total = 0,
		totalBytes = 0,
		mpps = {},
		mbit = {},
		wireMbit = {},
	}, rxCounter)
end

function rxCounter:update()
	local time = dpdk.getTime()
	if self.lastUpdate and time <= self.lastUpdate + 1 then
		return
	end
	if not self.lastUpdate then
		-- very first call, save current stats but do not print anything
		self.total, self.totalBytes = self.dev:getRxStats()
		self.lastTotal = self.total
		self.lastTotalBytes = self.totalBytes
		self.lastUpdate = time
		self:print("Init")
		return
	end
	local elapsed = time - self.lastUpdate
	self.lastUpdate = time
	local rxPkts, rxBytes = self.dev:getRxStats()
	self.total = self.total + rxPkts
	self.totalBytes = self.totalBytes + rxBytes
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

function rxCounter:print(event, ...)
	local func = formatters[self.format]["rxStats" .. event]
	if func then
		func(self, self.file, ...)
	end
end

function rxCounter:finalize()
	mod.addStats(self.mpps, true)
	mod.addStats(self.mbit, true)
	mod.addStats(self.wireMbit, true)
	self:print("Final")
	if self.closeFile then
		self.file:close()
	end
end

	--printf("Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", self.total, mpps, mpps * 64 * 8, mpps * 84 * 8)

return mod
