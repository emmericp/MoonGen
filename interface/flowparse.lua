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

local fmt = "[<file>/]<name>:[<tx-list>]:[<rx-list>]:[<option-list>]:[<overwrites>]"
return function(s, devnum)
	local name, tx, rx, optstring, overwrites = string.match(s, "^([^:]+)" .. (":?([^:]*)"):rep(3) .. ":?(.*)$")
	if not name or name == "" then
		log:fatal("Invalid parameter: %q.\nExpected format: '%s'."
			.. "\nAll lists are ',' seperated. Trailing ':' can be omitted.", s, fmt)
		return
	end

	local file, _name
	file, _name = string.match(name, "(.*)/([^/]+)")
	name = _name or name

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

	return {
		name = name, file = file,
		tx = parse_devices(tx, devnum, name),
		rx = parse_devices(rx, devnum, name),
		options = options, overwrites = overwrites
	}
end
