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


local mod = {}

function mod.newDevmgr()
	return setmetatable({}, {
		__index = function(tbl, key)
			if type(key) ~= "number" then
				return devicesClass[key]
			end
			local r = { rxq = 0, txq = 0, rxqi = 0, txqi = 0 }
			tbl[key] = r; return r
		end
	})
end

return mod
