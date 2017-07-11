return function(env, flows)
	function env.Flow(tbl)
		local name = tbl[1]
		local flow = {
			packet = {}
		}

		if tbl.parent then
			for i,v in pairs(flows[tbl.parent]) do
				if i == "packet" then
					for j,w in pairs(v) do
						flow.packet[i] = v
					end
				else
					flow[i] = v
				end
			end
		end

		for i,v in pairs(tbl[2]) do
			flow.packet[i] = v
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
