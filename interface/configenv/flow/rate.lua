local units = require "configenv.flow.units"

local function _parse_rate(rstring, psize)
	local num, unit, time = string.match(rstring, "^(%d+%.?%d*)(%a*)/?(%a*)$")
	if not num then
		return nil, "Invalid format. Should be '<number>[unit][/<time>]'."
	end

	num, unit, time = tonumber(num), string.lower(unit), units.time[time]
	if not time then
		return nil, unit.timeError
	end

	if unit == "" then
		unit = units.size.m --default is mbit/s
	elseif string.find(unit, "bit$") then
		unit = units.size[string.sub(unit, 1, -4)]
	elseif string.find(unit, "b$") then
		unit = units.size[string.sub(unit, 1, -2)] * 8
	elseif string.find(unit, "p$") then
		unit = units.size[string.sub(unit, 1, -2)] * psize * 8
	else
		return nil, unit.sizeError
	end

	unit = unit / 10 ^ 6 -- cbr is in mbit/s
	return num * unit / time
end


local option = {}

option.description = "Limit the rate of data from this flow. Will automatically"
	.. " fallback to software ratelimiting if needed."
option.configHelp = "Passing a number instead of a string will interpret the value as mbit/s."
function option.getHelp()
	return {
		{ "<number><sizeUnit>/<timeUnit>", "Default use case."},
		{ "<number><sizeUnit>", "Time unit defaults to seconds."},
		{ "<number>/<timeUnit>", "Size unit defaults to megabit."},
		{ "<number>", "Defaults to mbit/s."},
	}
end

function option.parse(self, rate)
	if type(rate) == "number" then
		self.cbr = rate
	elseif type(rate) == "string" then
		self.cbr = _parse_rate(rate, self:getPacketLength(true))
	end
end

function option.validate() end

function option.test(_, error, rate)
	local t = type(rate)

	if t == "string" then
		local status, msg = _parse_rate(rate, 1)
		error:assert(status, 4, "Option 'rate': %s", msg)
		return type(status) ~= "nil"
	elseif t ~= "number" and t ~= "nil" then
		error(4, "Option 'rate': Invalid argument. String or number expected, got %s.", t)
		return false
	end

	return true
end

return option
