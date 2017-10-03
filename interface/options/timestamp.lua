local units = require "units"

local option = {}

option.description = "Start a second timestamped version of this flow. (default=false)"
option.configHelp = "Will also accept boolean values."
option.usage = {
	{ "<boolean>", "Default use case."},
	{ nil, "Set option to true."},
}

function option.parse(self, bool, error)
	bool = units.parseBool(bool, false, error)

	if bool and not error:assert(#self:property("rx") == 1,
		"Cannot timestamp flows with more than one receiving device.") then
		return false
	end

	return bool
end

return option
