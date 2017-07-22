local Packet = {}

function Packet.new(proto, tbl, error)
	local self = {
		proto = proto,
		fillTbl = {},
		dynvars = {}
	}

	for i,v in pairs(tbl) do
		local pkt, var = string.match(i, "^([%l%d]+)(%u[%l%d]*)$");

		if pkt then
			if type(v) == "function" then
				var = string.lower(var)
				table.insert(self.dynvars, {
					pkt = pkt, var = var, func = v
				})
				v = v() -- NOTE arp will execute in master
			end

			self.fillTbl[i] = v
		else
			error("Invalid packet field %q.", i) -- TODO add hint?
		end
	end

	return setmetatable(self, { __index = Packet })
end

function Packet:inherit(other)
	if other then
		for i,v in pairs(other.fillTbl) do
			if not self.fillTbl[i] then
				self.fillTbl[i] = v
			end
		end

		local dynvarIndex = {}
		for _,v in ipairs(self.dynvars) do
			dynvarIndex[v.pkt .. "_" .. v.var] = true
		end

		for _,v in ipairs(other.dynvars) do
			if dynvarIndex[v.pkt .. "_" .. v.var] then
				table.insert(self.dynvars, v)
			end
		end
	end

	return self
end

function Packet:validate(val)
	val:assert(type(self.fillTbl.pktLength) == "number",
		"Packet field pktLength has to be set to a valid number.")
end

return Packet
