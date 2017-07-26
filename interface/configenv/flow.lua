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
	local parent = tbl.parent

	local self = {
		name = name, parent = parent,
		-- TODO figure out actual queue requirements
		tx_txq = 1, tx_rxq = 1, rx_txq = 1, rx_rxq = 1,
		packet = tbl[2]:inherit(parent and parent.packet)
	}

	for i in pairs(_option_list) do
		self[i] = tbl[i] or (parent and parent[i])
	end

	return setmetatable(self, { __index = Flow })
end

function Flow:validate(val)
	self.packet:validate(val)

	for name, ops in pairs(_option_list) do
		local v = self.options[name] or self[name]
		if v then
			ops.validate(val, v)
		end
	end
end

function Flow:prepare()
	for name, ops in pairs(_option_list) do
		local v = self.options[name] or self[name]
		if v then
			ops.parse(self, v)
		end
	end
end

return Flow
