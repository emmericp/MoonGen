local units = require "units"

local option = {}

option.description = "Set the payload to a unique value to allow generating per-flow stats. (default = true)"
option.configHelp = "Will also accept boolean values."
function option.getHelp()
	return {
		{ "<boolean>", "Default use case."},
		{ nil, "Set option to true."},
	}
end

function option.parse(self, bool, error)
  bool = units.parseBool(bool, false, error)

  if not self.packet.hasPayload then
    error:assert(not bool, "Set to true, but packet cannot carry payloads.")
    return false
  end

	return bool
end

return option
