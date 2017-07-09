return function(env, flows)
	function env.Flow(tbl)
		local name = tbl[1]
		local flow = {}

--[[
	NOTE support multiple?, intended order:
		paket1 variation1,
		paket2 variation1, ...
		paketN variation1,
		paket1 variation2, ...
]]

		for i = 2, #tbl do
			flow[i - 1] = tbl[i]
		end

		flows[name] = flow
	end

	env.Packet = setmetatable({}, {
		__newindex = function() error() end,
		__index = function(_, proto)
			return function(tbl)
				local packet = {}
				packet.proto = proto

				packet.fillTbl = {}
				packet.dynvars = {}
				for i,v in pairs(tbl) do
					local pkt, var = string.match(i, "^([%l%d]+)(%u[%l%d]*)$");

					if type(v) == "function" then
						var = string.lower(var)
						table.insert(packet.dynvars, {
							pkt = pkt, var = var, func = v
						})
						v = v() -- NOTE arp will execute in master
					end

					packet.fillTbl[i] = v
				end
				return packet
			end
		end
	})
end
