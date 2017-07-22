local Flow = {}

local _option_list = "rate"

function Flow.new(name, tbl)
	local parent = tbl.parent
	local self = {
		name = name,
		-- TODO figure out actual queue requirements
		tx_txq = 1, tx_rxq = 1, rx_txq = 1, rx_rxq = 1,
		packet = tbl[2]:inherit(parent and parent.packet)
	}

	if parent then
		self.parent = parent.name
		-- NOTE add copy opertations here
	end
	return setmetatable(self, { __index = Flow })
end

function Flow:validate(val)
	self.packet:validate(val)
	-- TODO more validation
end

local _time_units = {
	[""] = 1, ms = 1 / 1000, s = 1, m = 60, h = 3600
}
local _size_units = {
	[""] = 1,
	k = 10 ^ 3, ki = 2 ^ 10,
	m = 10 ^ 6, mi = 2 ^ 20,
	g = 10 ^ 9, gi = 2 ^ 30
}
local function _parse_rate(self)
	local num, unit, time = string.match(self.options.rate, "^(%d+%.?%d*)(%a*)/?(%a*)$")
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
end

function Flow:prepare()
	-- update options
	for opt in string.gmatch(_option_list, "%w+") do
		if not self.options[opt] then
			self.options[opt] = self[opt]
		end
	end

	if self.options.rate then
		_parse_rate(self)
	end
end

return Flow
