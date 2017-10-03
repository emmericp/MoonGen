local units = require "units"

local option = {}

option.description = "Stop sending this flow after a certain time, starting with"
	.. " the first packet sent. Time will only be checked after a full buffer"
	.. " has been sent (usually 64 packets). For this reason, the actual time"
	.. " passed between first and last packet might be longer, but should never"
	.. " be shorter than expected."
option.configHelp = "Passing a number instead of a string will interpret the value as number of seconds."
option.usage = { { "<number><timeUnit>", "Default use case." } }


local function _parse_limit(lstring)
	local num, unit = string.match(lstring, "^(%d+%.?%d*)(%a+)$")
	if not num then
		return nil, "Invalid format. Should be '<number><unit>'."
	end

	num, unit = tonumber(num), units.time[string.lower(unit)]
	if not unit then
		return nil, unit.timeError
	end

	return num, unit
end

function option.parse(_, limit, error)
	if not limit then return end

	local t = type(limit)

	local num, unit
	if t == "number" then
		num, unit = limit, units.time.s
	elseif t == "string" then
		num, unit = _parse_limit(limit)
		error:assert(num, unit)
	else
		error("Invalid argument. String or number expected, got %s.", t)
	end

	if num then
		return num * unit
	end
end

return option
