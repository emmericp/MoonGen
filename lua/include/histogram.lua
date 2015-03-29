local histogram = {}
histogram.__index = histogram

function histogram:create()
	local histo = setmetatable({}, histogram)
	histo.histo = {}
	histo.dirty = true
	return histo
end

histogram.new = histogram.create

setmetatable(histogram, { __call = histogram.create })

function histogram:update(k)
	self.histo[k] = (self.histo[k] or 0) +1
	self.dirty = true
end

function histogram:calc()
	self.sortedHisto = {}
	self.sum = 0
	self.numSamples = 0

	for k, v in pairs(self.histo) do
		table.insert(self.sortedHisto, { k = k, v = v })
		self.numSamples = self.numSamples + v
		self.sum = self.sum + k * v
	end
	self.avg = self.sum / self.numSamples
	local stdDevSum = 0
	for k, v in pairs(self.histo) do
		stdDevSum = stdDevSum + v * (k - self.avg)^2
	end
	self.stdDev = (stdDevSum / (self.numSamples - 1)) ^ 0.5

	table.sort(self.sortedHisto, function(e1, e2) return e1.k < e2.k end)
	
	-- TODO: this is obviously not entirely correct for numbers not divisible by 4
	-- however, it doesn't really matter for the number of samples we usually use
	local quartSamples = self.numSamples / 4

	self.quarts = {}

	local idx = 0
	for _, p in ipairs(self.sortedHisto) do
		-- TODO: inefficient
		for _ = 1, p.v do
			if not self.quarts[1] and idx >= quartSamples then
				self.quarts[1] = p.k
			elseif not self.quarts[2] and idx >= quartSamples * 2 then
				self.quarts[2] = p.k
			elseif not self.quarts[3] and idx >= quartSamples * 3 then
				self.quarts[3] = p.k
				break
			end
			idx = idx + 1
		end
	end
	self.dirty = false
end

function histogram:totals()
	if self.dirty then self:calc() end

	return self.numSamples, self.sum, self.avg
end

function histogram:avg()
	if self.dirty then self:calc() end

	return self.avg
end

function histogram:standardDeviation()
	if self.dirty then self:calc() end

	return self.stdDev
end

function histogram:quartiles()
	if self.dirty then self:calc() end
	
	return unpack(self.quarts)
end

function histogram:median()
	if self.dirty then self:calc() end

	return self.quarts[2]
end

function histogram:samples()
	local i = 0
	if self.dirty then self:calc() end
	local n = #self.sortedHisto
	return function()
		if not self.dirty then
			i = i + 1
			if i <= n then return self.sortedHisto[i] end
		end
	end
end

-- FIXME: add support for different formats
function histogram:print()
	if self.dirty then self:calc() end

	printf("Samples: %d, Average: %.1f, StdDev: %.1f, Quartiles: %.1f/%.1f/%.1f", self.numSamples, self.avg, self.stdDev, unpack(self.quarts))
end

return histogram

