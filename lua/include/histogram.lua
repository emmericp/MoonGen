histogram = {}
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
    return self.sortedHisto
end

function histogram:stat()
        if not self.sortedHisto then self:calc() end

        local quart_samples = self.samples / 4

        self.lower_quart = nil
        self.median = nil
        self.upper_quart = nil

        local idx = 0
        for dummy, p in pairs(self.sortedHisto) do
                if not self.lower_quart and idx >= quart_samples then
                        self.lower_quart = p.k
                elseif not self.median and idx >= quart_samples * 2 then
                        self.median = p.k
                elseif not self.upper_quart and idx >= quart_samples * 3 then
                        self.upper_quart = p.k
                        break
                end

                idx = idx + p.v
        end
end

return histogram
