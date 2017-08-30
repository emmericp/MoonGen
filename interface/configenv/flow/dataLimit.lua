local units = require "configenv.flow.units"

local option = {}

option.description = "Stop sending this flow after a certain amount of data. As"
	.. " flows should only be cut short at a whole number of packets sent, every"
	.. " value passed will be rounded up to the nearest whole number of packets."
option.configHelp = "Passing a number instead of a string will interpret the value as megabit."
function option.getHelp()
	return { { "<number><sizeUnit>", "Default use case." } }
end

local function _parse_limit(lstring, psize)
	local num, unit = string.match(lstring, "^(%d+%.?%d*)(%a+)$")
	if not num then
		return nil, "Invalid format. Should be '<number><unit>'."
	end

	num, unit = tonumber(num), string.lower(unit)
	if unit == "" then
		unit = units.size.m --default is mbit
	elseif string.find(unit, "bit$") then
		unit = units.size[string.sub(unit, 1, -4)]
	elseif string.find(unit, "b$") then
		unit = units.size[string.sub(unit, 1, -2)] * 8
	elseif string.find(unit, "p$") then
		unit = units.size[string.sub(unit, 1, -2)] * psize * 8
	else
		return nil, unit.sizeError
	end

	return num, unit
end

function option.parse(self, limit)
	local psize = self:getPacketLength(true)

	local num, unit
	if type(limit) == "number" then
		num, unit = limit, units.size.m
	elseif type(limit) == "string" then
		num, unit = _parse_limit(limit, psize)
	end

	-- round up to mimic behaviour of timeLimit
	if num then
		self.dlim = math.ceil(num * unit / (psize * 8))
	end
end

function option.validate() end

function option.test(_, error, limit)
	local t = type(limit)

	if t == "string" then
		local status, msg = _parse_limit(limit, 1)
		error:assert(status, 4, "Option 'dataLimit': %s", msg)
		return type(status) ~= "nil"
	elseif t ~= "number" and t ~= "nil" then
		error(4, "Option 'dataLimit': Invalid argument. String or number expected, got %s.", t)
		return false
	end

	return true
end

return option
