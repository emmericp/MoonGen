local Flow = {}

local _time_units = {
	[""] = 1, ms = 1 / 1000, s = 1, m = 60, h = 3600
}
local _size_units = {
	[""] = 1,
	k = 10 ^ 3, ki = 2 ^ 10,
	m = 10 ^ 6, mi = 2 ^ 20,
	g = 10 ^ 9, gi = 2 ^ 30
}

local _option_list = {
	rate = {
		parse = function(self, rate)
			if type(rate) == "number" then
				self.cbr = rate
				return
			end

			local num, unit, time = string.match(rate, "^(%d+%.?%d*)(%a*)/?(%a*)$")
			num, unit, time = tonumber(num), string.lower(unit), _time_units[time]

			if unit == "" then
				unit = _size_units.m * 8
			elseif string.find(unit, "bit$") then
				unit = _size_units[string.sub(unit, 1, -4)]
			elseif string.find(unit, "b$") then
				unit = _size_units[string.sub(unit, 1, -2)] * 8
			elseif string.find(unit, "p$") then
				unit = _size_units[string.sub(unit, 1, -2)] * self.packet:size()
			end

			unit = unit / 10 ^ 6 -- cbr is in mbit/s
			self.cbr = num * unit / time
		end,
		validate = function(val, rate)
			if type(rate) ~= "number" then
				val:assert(string.match(rate, "^(%d+%.?%d*)(%a*)/?(%a*)$"),
					"Invalid value for option 'rate.'")
			end
		end
	}
}

function Flow.new(name, tbl)
	tbl.name, tbl.packet = name, tbl[2]

	-- TODO figure out actual queue requirements
	tbl.tx_txq, tbl.tx_rxq, tbl.rx_txq, tbl.rx_rxq = 1, 1, 1, 1

	if tbl.parent then
		local parent = tbl.parent
		tbl.packet:inherit(parent.packet)

		for i in pairs(_option_list) do
			if not tbl[i] then
				tbl[i] = parent[i]
			end
		end
	end

	return setmetatable(tbl, { __index = Flow })
end

local _flow_ignored = {}
for _,v in ipairs{ 1, 2, "name", "tx_txq", "tx_rxq", "rx_txq", "rx_rxq" } do
	_flow_ignored[v] = true
end
function Flow:validate(val)
	for i,v in pairs(self) do
		if _flow_ignored[i] then -- luacheck: ignore
		elseif i == "packet" then
			v:validate(val)
		else
			local opt = _option_list[i]
			val:assert(opt, "Unknown field %q in flow %q.", i, self.name)
			if opt then
				opt:validate(val, v)
			end
		end
	end
end

function Flow:prepare()
	for name, opt in pairs(_option_list) do
		local v = self.options[name] or self[name]
		if v then
			opt.parse(self, v)
		end
	end
end

return Flow
