local units = require "units"

local option = {}

option.description = "Set the payload to a unique value to allow generating per-flow stats. (default = true)"
option.configHelp = "Will also accept boolean values."
option.usage = {
	{ "<boolean>", "Default use case."},
	{ nil, "Set option to true."},
}

function option.parse(self, bool, error)
  bool = units.parseBool(bool, false, error)

	local len = self.packet.fillTbl.pktLength
  if not self.packet.hasPayload then
    error:assert(not bool, "Set to true, but packet cannot carry payloads.")
    return false
	elseif len < 60 then -- Needs 60 bytes to fit uid at the end of the ethernet frame
    error:assert(not bool, "Set to true, but packet is not large enough to carry uid information."
			.. " Needs at least 60 bytes.")
		return false
  elseif len < self.packet.minSize + 4 then
    error:assert(not bool, "Set to true, but packet is not large enough to carry uid information."
			.. " Needs at least 4 bytes above the minimum size.")
		return false
	end

	return bool
end

return option
