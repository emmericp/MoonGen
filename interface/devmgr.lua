local device = require "device"

local devicesClass = {}

function devicesClass:reserveTx(tx)
	self[tx].txq = self[tx].txq + 1
end

function devicesClass:reserveRx(rx)
	self[rx].rxq = self[rx].rxq + 1
end

function devicesClass:reserveRss(rss)
	self[rss].rxq = self[rss].rxq + 1
	self[rss].rsq = self[rss].rsq + 1
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
	return self[rx].dev:getRxQueue(self[rx].rsq + _inc(self[rx], "rxqi"))
end

function devicesClass:rssQueue(rx)
	return self[rx].dev:getRxQueue(_inc(self[rx], "rsqi"))
end

function devicesClass:configure()
	for i,v in pairs(self) do
		local txq, rxq = v.txq, v.rxq
		txq, rxq = (txq == 0) and 1 or txq, (rxq == 0) and 1 or rxq
		v.dev = device.config{ port = i, rxQueues = rxq, rssQueues = v.rsq, txQueues = txq }
	end

	device.waitForLinks()
end


local mod = {}

function mod.newDevmgr()
	return setmetatable({ }, {
		__index = function(tbl, key)
			if key == "max" then
				return device.numDevices()
			elseif type(key) ~= "number" then
				return devicesClass[key]
			end
			local r = { rxq = 0, rsq = 0, txq = 0, rxqi = 0, rsqi = 0, txqi = 0 }
			tbl[key] = r; return r
		end
	})
end

return mod
