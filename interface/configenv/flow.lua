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
		test = function(error, rate)
			local t = type(rate)
			if t == "string" then
				error:assert(string.match(rate, "^(%d+%.?%d*)(%a*)/?(%a*)$"), 3,
					"Invalid value for option 'rate.'")
			elseif t ~= "number" then
				error(3, "Invalid value for option 'rate': string or number expected, got %s.", t)
			end
		end
	}
}

function Flow.new(name, tbl, error)
	local self = { name = name, packet = tbl[2], parent = tbl.parent }
	tbl[1], tbl[2], tbl.parent = nil, nil, nil

	-- TODO figure out actual queue requirements
	self.tx_txq, self.tx_rxq, self.rx_txq, self.rx_rxq = 1, 1, 1, 1

	-- check and copy options
	for i,v in pairs(tbl) do
		local opt = _option_list[i]

		if opt then
			if (not opt.test) or opt.test(error, v) then
				self[i] = v
			end
		else
			error(4, "Unknown field %q in flow %q.", i, name)
		end
	end

	if type(self.parent) == "table" then
		local parent = self.parent
		self.packet:inherit(parent.packet)

		-- copy parent options
		for i in pairs(_option_list) do
			if not self[i] then
				self[i] = parent[i]
			end
		end
	end

	return setmetatable(self, { __index = Flow })
end

function Flow:validate(val)
	self.packet:validate(val)

	-- validate options
	for i,opt in pairs(_option_list) do
		local v = self[i]
		if v and opt.validate then
			opt.validate(val, v)
		end
	end
end

-- TODO test dynamic options

function Flow:prepare()
	for name, opt in pairs(_option_list) do
		local v = self.options[name] or self[name]
		if v then
			opt.parse(self, v)
		end
	end
end

return Flow
