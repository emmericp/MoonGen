local histogram = {}
histogram.__index = histogram

function histogram.create()
	local histo = {}
	setmetatable(histo, histogram)
	histo.histo = {}
	return histo
end

function histogram:update(k)
	self.histo[k] = (self.histo[k] or 0) +1
end

function histogram:sort()
	self.sortedHisto = {}
	self.sum = 0
	self.samples = 0

	for k, v in pairs(self.histo) do
		table.insert(self.sortedHisto, { k = k, v = v})
		self.samples = self.samples + v
		self.sum = self.sum + k * v
	end
	table.sort(self.sortedHisto, function(e1, e2) return e1.k < e2.k end)
	return self.sortedHisto
end

return histogram
