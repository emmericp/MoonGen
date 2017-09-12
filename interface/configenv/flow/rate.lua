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

function option.parse(self, rate, error)
	if not rate then return end

	local t = type(rate)

	local cbr
	if t == "number" then
		cbr = rate
	elseif t == "string" then
		local msg
		cbr, msg = _parse_rate(rate, self:getPacketLength(true))
		error:assert(cbr, msg)
	else
		error("Invalid argument. String or number expected, got %s.", t)
	end

	return cbr
end

return option
