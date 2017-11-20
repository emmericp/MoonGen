local units = {}

units.time = {
	[""] = 1,
	ms = 1 / 1000,
	s  = 1,
	m  = 60,
	h  = 3600,
}
units.timeError  = "Invalid time unit. Can be one of 'ms', 's', 'm', 'h'."

units.size = {
	[""] = 1,
	k = 10 ^ 3, ki = 2 ^ 10,
	m = 10 ^ 6, mi = 2 ^ 20,
	g = 10 ^ 9, gi = 2 ^ 30,
}
units.sizeError = "Invalid size unit. Can be <k|m|g>[i]<bit|b|p>"

units.bool = {
	["0"] = false, ["1"] = true,
	["false"] = false, ["true"] = true,
	["no"] = false, ["yes"] = true,
}
units.boolError = "Invalid boolean. Can be one of (0|false|no) or (1|true|yes) respectively."

function units.parseBool(bool, default, error)
	local t = type(bool)

	if t == "string" then
		bool = units.bool[bool]
		if not error:assert(type(bool) == "boolean", units.boolError) then
			return default
		end
	elseif t == "nil" then
		return default
	elseif t ~= "boolean" then
		error("Invalid argument. String or boolean expected, got %s.", t)
	end

	return bool
end

return units
