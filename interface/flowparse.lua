local log = require "log"

local function parse_devices(s, devnum, name)
	local result = {}

	for num in string.gmatch(s, "([^,]+)") do
		if num ~= "" then
			local n = tonumber(num)
			if not n or n < 0 or n >= devnum then
				log:error("Invalid device number %q for flow %q.", num, name)
			else
				table.insert(result, n)
			end
		end
	end

	return result
end

return function(s, devnum)
	local name, tx, rx, optstring = string.match(s, "^([^:]+):([^:]*):([^:]*):?(.*)$")
	if not name then
		log:fatal("Invalid parameter: %q. Expected format: '<name>:{<devnum>}:{<devnum>}[:{<option>}]'."
			.. " All options are comma (',') seperated.", s)
	end

	local options = {}
	for opt in string.gmatch(optstring, "([^,]+)") do
		if opt ~= "" then
			local k, v = string.match(opt, "^([^=]+)=([^=]+)$")
			if not k then
				k, v = opt, true
			end
			options[k] = v
		end
	end

	return name, parse_devices(tx, devnum, name), parse_devices(rx, devnum, name), options
end
