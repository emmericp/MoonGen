local Flow = require "configenv.flow"
local Packet = require "configenv.packet"

return function(env, error, flows)
		function env.Flow(tbl)
			local name = tbl[1]

			-- check for characters that
			-- - would complicate shell argument parsing ( ;)
			-- - interfere with flow parameter syntax (:,)
			if string.find(name, "[ ;:,]") then
				error("Invalid flow name %q. Names cannot include the characters ' ;:,'.", name)
			end

			flows[name] = Flow.new(name, tbl, error)
		end

		env.Packet = setmetatable({}, {
			__newindex = function() error() end, -- TODO message
			__index = function(_, proto)
				return function(tbl)
					return Packet.new(proto, tbl, error)
				end
			end
		})
end
