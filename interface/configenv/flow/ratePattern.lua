local _patternlist, _patternset = { "cbr", "poisson" }, {}
-- TODO pattern = custom (closure and buf:setDelay)
-- TODO flagOption to enable crc ratecontrol
for _,v in ipairs(_patternlist) do
	_patternset[v] = true
end

local option = {}

option.description = "Control how bytes are distributed over time, when a ratelimit is set."
function option.getHelp()
	return { { "(cbr|poisson)", "Poisson will create bursts of packets instead of a constant bitrate. (default = cbr)" } }
end

function option.parse(self, pattern)
	self.rpattern = _patternset[pattern] and pattern or "cbr"
end

function option.validate() end

function option.test(_, error, pattern)
	local t = type(pattern)
	if t == "string" then
		if not _patternset[string.lower(pattern)] then
			error(4, "Option 'ratePattern': Invalid value %q. Can be one of %s.",
				pattern, table.concat(_patternlist, ", "))
			return false
		end
	else
		error(4, "Option 'ratePattern': Invalid argument. String expected, got %s.", t)
		return false
	end

	return true
end

return option
