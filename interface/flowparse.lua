local log = require "log"

return function(s, devnum)
	local name, devstring, optstring = string.match(s, "^([^:,]+):?([^,]*),?(.*)$")
	if not name then
		log:fatal("Invalid parameter: %q. Expected format: '<name>{:<devnum>{.<devnum>}}{,<key>=<value>}'.", s)
	end

	local tx_rx = {}
	for nums in string.gmatch(devstring, "([^:]+)") do
		local devices = {}
		for num in string.gmatch(nums, "([^.]+)") do
			local n = tonumber(num)
			if not n or n < 0 or n >= devnum then
				log:error("Invalid device number %q for flow %q.", num, name)
			else
				table.insert(devices, n)
			end
		end
		table.insert(tx_rx, devices)
	end

	local options = {}
	for opt in string.gmatch(optstring, "([^,]+)") do
		local k, v = string.match(opt, "^([^=]+)=([^=]+)$")
		if not k then
			k, v = opt, true
		end
		options[k] = v
	end

	return name, tx_rx, options
end
