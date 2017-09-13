local Flow = require "flow"
local Packet = require "flow.packet"

return function(env, error, flows)
		function env.Flow(tbl)
			if type(tbl) ~= "table" then
				error("Invalid usage of Flow. Try Flow{...)")
				return
			end

			-- check name, disallow for characters that
			-- - would complicate shell argument parsing ( ;)
			-- - interfere with flow parameter syntax (:,)
			local name = tbl[1]
			local t = type(name)
			if  t ~= "string" then
				error("Invalid flow name. String expected, got %s.", t)
				name = nil
			elseif name == "" then
				error("Flow name cannot be empty.")
				name = nil
			elseif string.find(name, "[ ;:,]") then
				error("Invalid flow name %q. Names cannot include the characters ' ;:,'.", name)
				name = nil
			end

			-- find instace of parent flow
			local pname = tbl.parent
			t = type(pname)
			if t == "string" then
				local parent = flows[pname]
				error:assert(parent, "Unknown parent %q of flow %q.", pname, name)
				tbl.parent = parent
			elseif t ~= "table" and t ~= "nil" then
				error("Invalid value for parent of flow %q. String or flow expected, got %s.", name, t)
			end

			-- add to list of flows if name is valid
			local flow = Flow.new(name, tbl, error)
			if name then
				flows[name] = flow
			end

			return flow
		end

		local packetmsg = "Invalid usage of Packet. Try Packet.proto{...}."
		local function _packet_error() error(packetmsg) end
		env.Packet = setmetatable({}, {
			__newindex = _packet_error,
			__call = _packet_error,
			__index = function(_, proto)
				if type(proto) ~= "string" then
					error(packetmsg)
					return function() end
				end

				return function(tbl)
					if type(tbl) ~= "table" then
						error(packetmsg)
					else
						return Packet.new(proto, tbl, error)
					end
				end
			end
		})
end
