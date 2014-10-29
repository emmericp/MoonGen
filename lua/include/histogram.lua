local histogram = {}
histogram.__index = histogram

function histogram.create()
	local histo = {}
	setmetatable(histo, histogram)
	histo.histo = {}
	histo.dirty = true
	return histo
end

function histogram:update(k)
	self.histo[k] = (self.histo[k] or 0) +1
	self.dirty = true
end

function histogram:calc()
	self.sortedHisto = {}
	self.sum = 0
	self.samples = 0

	for k, v in pairs(self.histo) do
		table.insert(self.sortedHisto, { k = k, v = v})
		self.samples = self.samples + v
		self.sum = self.sum + k * v
	end
	self.avg = self.sum / self.samples
	table.sort(self.sortedHisto, function(e1, e2) return e1.k < e2.k end)
	
	local quartSamples = self.samples / 4

	self._lowerQuart = nil
	self._median = nil
	self._upperQuart = nil

	local idx = 0
	for _, p in ipairs(self.sortedHisto) do
			if not self._lowerQuart and idx >= quartSamples then
					self._lowerQuart = p.k
			elseif not self._median and idx >= quartSamples * 2 then
					self._median = p.k
			elseif not self._upperQuart and idx >= quartSamples * 3 then
					self._upperQuart = p.k
					break
			end

			idx = idx + p.v
	end
	self.dirty = false
end

function histogram:quartiles()
	if self.dirty then self:calc() end

	return self._lowerQuart, self._median, self._upperQuart
end

function histogram:samples()
	local i = 0
	if self.dirty then self:calc() end
	local n = #(self.sortedHisto)
	return function ()
		if not self.dirty then
			i = i+1
			if i <= n then return self.sortedHisto[i] end
		end
	end
end

return histogram
