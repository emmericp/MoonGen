local function _init_tbl(tbl, key)
	local result = tbl[key]
	if not result then
		result = {}
		tbl[key] = result
	end
	return result
end

local function _copy_packet(src, dest)
	if dest.proto then
		assert(dest.proto == src.proto) -- TODO error message
	else
		dest.proto = src.proto
	end


	local tbl = _init_tbl(dest, "fillTbl")
	for i,v in pairs(src.fillTbl) do
		tbl[i] = v
	end

	tbl = _init_tbl(dest, "dynvars")
	for _,v in ipairs(src.dynvars) do
		table.insert(tbl, v)
	end
end

return function(env, error, flows)
	function env.Flow(tbl)
		local name = tbl[1]
		error.assert(not string.find(name, ","), "Invalid character ',' in flow name.")
		error.assert(not string.find(name, ":"), "Invalid character ':' in flow name.")
		error.assert(not string.find(name, " "), "Invalid character ' ' in flow name.")

		local flow = {
			packet = {}
		}

		if tbl.parent then
			for i,v in pairs(flows[tbl.parent]) do
				if i == "packet" then
					_copy_packet(v, flow.packet)
				else
					flow[i] = v
				end
			end
		end

		flow.name = name
		_copy_packet(tbl[2], flow.packet)

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
