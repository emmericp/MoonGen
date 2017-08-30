local units = require "configenv.flow.units"

local option = {}

option.description = "Stop sending this flow after a certain time, starting with"
	.. " the first packet sent. Time will only be checked after a full buffer"
	.. " has been sent (usually 64 packets). For this reason, the actual time"
	.. " passed between first and last packet might be longer, but should never"
	.. " be shorter than expected."
option.configHelp = "Passing a number instead of a string will interpret the value as number of seconds."
function option.getHelp()
	return { { "<number><timeUnit>", "Default use case." }}
end


local function _parse_limit(lstring)
	local num, unit = string.match(lstring, "^(%d+%.?%d*)(%a+)$")
	if not num then
		return nil, "Invalid format. Should be '<number><unit>'."
	end

	num, unit = tonumber(num), units.time[string.lower(unit)]
	if not unit then
		return nil, unit.timeError
	end

	return num * unit
end

function option.parse(self, limit)
	if type(limit) == "number" then
		self.tlim = limit
	elseif type(limit) == "string" then
		self.tlim = _parse_limit(limit)
	end
end

function option.validate() end

function option.test(_, error, limit)
	local t = type(limit)

	if t == "string" then
		local status, msg = _parse_limit(limit, 1)
		error:assert(status, 4, "Option 'timeLimit': %s", msg)
		return type(status) ~= "nil"
	elseif t ~= "number" and t ~= "nil" then
		error(4, "Option 'timeLimit': Invalid argument. String or number expected, got %s.", t)
		return false
	end

	return true
end

return option
