local units = require "units"

local option = {}

option.description = "Set the payload to a unique value to allow generating per-flow stats."
	..	" (default = true if possible)\nSet to true to check error messages when a flow"
	..  " does not use this by default."
option.configHelp = "Will also accept boolean values."
option.usage = {
	{ "<boolean>", "Default use case."},
	{ nil, "Set option to true."},
}

function option.parse(self, bool, error)
	local len = self:packetSize()

	local hasPayload = self.packet.hasPayload
	local fillsEthFrame = len >= 60
	local hasSpace = len >= self.packet.minSize + 4

  bool = units.parseBool(bool, hasPayload and fillsEthFrame and hasSpace, error)

  if bool then
    bool = bool and error:assert(hasPayload, "Set to true, but packet cannot carry payloads.")
    bool = bool and error:assert(fillsEthFrame, "Set to true, but packet is not large enough to carry uid information."
			.. " Needs at least 60 bytes.")
    bool = bool and error:assert(hasSpace, "Set to true, but packet is not large enough to carry uid information."
			.. " Needs at least 4 bytes above the minimum size of %d.", self.packet.minSize)
	end

	return bool
end

return option
