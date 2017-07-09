local arp = require "proto.arp"

return function(env)

<<<<<<< HEAD
	-- luacheck: read globals parseIPAddress
	env.ip = function(str)
		return (parseIPAddress(str))
	end

	-- luacheck: read globals parseMacAddress
	env.mac = function(str)
		return (parseMacAddress(str, true))
	end

=======
	env.ip = function(str)
		return (parseIPAddress(str))
	end
	env.mac = function(str)
		return (parseMacAddress(str))
	end
	
	
>>>>>>> 1860b17cb5d4c9f87f676b488f28460953b87883
	-- arp(ip:ip_addr, timeout:number = 5)
	-- TODO consider deducing ip
	env.arp = function(ip, timeout)
		timeout = timeout or 5
		-- TODO input assertions

		local result
		return function()
			if timeout then
				result = arp.blockingLookup(ip, timeout)
				timeout = nil
			end
			return result
		end
	end

end
