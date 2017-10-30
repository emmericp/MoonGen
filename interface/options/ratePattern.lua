local _patternlist, _patternset = { "cbr", "poisson" }, {}
-- TODO pattern = custom (closure and buf:setDelay)
-- TODO flagOption to enable crc ratecontrol
for _,v in ipairs(_patternlist) do
	_patternset[v] = true
end

local option = {}

option.description = "Control how bytes are distributed over time, when a ratelimit is set."
option.usage = {
	{ "(cbr|poisson)", "Poisson will create bursts of packets instead of a constant bitrate. (default = cbr)" }
}

function option.parse(_, pattern, error)
	local t = type(pattern)

	if t == "string" then
		return error:assert(_patternset[pattern], "Invalid value %q. Can be one of %s.",
		  pattern, table.concat(_patternlist, ", ")) or "cbr"
	elseif t ~= "nil" then
		error("Invalid argument. String expected, got %s.", t)
	end

	return "cbr"
end

return option
