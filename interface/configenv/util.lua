local arp = require "proto.arp"

return function(env)

	env.ip = function(str)
		return (parseIPAddress(str))
	end
	env.mac = function(str)
		return (parseMacAddress(str))
	end
	
	
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
