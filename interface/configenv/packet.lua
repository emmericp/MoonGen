local Dynvars = require "configenv.dynvars"

local Packet = {}

function Packet.new(proto, tbl, error)
	local self = {
		proto = proto,
		fillTbl = {},
		dynvars = Dynvars.new()
	}

	for i,v in pairs(tbl) do
		local pkt, var = string.match(i, "^([%l%d]+)(%u[%l%d]*)$");

		if pkt then
			if type(v) == "function" then
				var = string.lower(var)
				v = self.dynvars:add(pkt, var, v).value
			end

			self.fillTbl[i] = v
		else
			error("Invalid packet field %q. Format is 'layerField' (e.g. ip4Dst).", i)
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

		self.dynvars:inherit(other.dynvars)
	end

	return self
end

function Packet:size()
	return self.fillTbl.pktLength
end

function Packet:prepare()
	if not self.prepared then
		self.dynvars:finalize()
		self.prepared = true
	end
end

function Packet:validate(val)
	val:assert(type(self.fillTbl.pktLength) == "number",
		"Packet field pktLength has to be set to a valid number.")
end

return Packet
