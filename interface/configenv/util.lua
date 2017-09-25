return function(env)
	function env.ip(str)
		local t = type(str)
		if t ~= "string" then
			env.error("Function 'ip': string expected, got %s.", t)
			return
		end

		-- luacheck: read globals parseIPAddress
		local ip = parseIPAddress(str)
		env.error:assert(ip, "Invalid ip address %q.", str)
		return ip
	end

	function env.mac(str)
		local t = type(str)
		if t ~= "string" then
			env.error("Function 'mac': string expected, got %s.", t)
			return
		end

		-- luacheck: read globals parseMacAddress
		local mac = parseMacAddress(str, true)
		env.error:assert(mac, "Invalid mac address %q.", str)
		return mac
	end
end
