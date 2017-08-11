local log = require "log"

return function(s, devnum)
	local name, devstring, optstring = string.match(s, "^([^:,]+):?([^,]*),?(.*)$")
	if not name then
		log:fatal("Invalid parameter: %q. Expected format: '<name>{:<devnum>}{,<key>=<value>}'.", s)
	end

	local devices = {}
	for num in string.gmatch(devstring, "([^:]+)") do
		local n = tonumber(num)
		if not n or n < 0 or n >= devnum then
			log:error("Invalid device number %q for flow %q.", num, name)
		else
			table.insert(devices, n)
		end
	end

	local options = {}
	for opt in string.gmatch(optstring, "([^,]+)") do
		local k, v = string.match(opt, "^([^=]+)=([^=]+)$")
		if not k then
			k, v = opt, true
		end
		options[k] = v
	end

	return name, devices, options
end
