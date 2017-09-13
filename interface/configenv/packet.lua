local packet = require "packet"
local ffi    = require "ffi"

local Dynvars = require "configenv.dynvars"

local Packet = {}
Packet.__index = Packet

ffi.cdef[[
	struct test_packet_t {};
]]

local test_packet = ffi.metatype("struct test_packet_t", {
	__index = {
		getLength = function(self) return 0 end,
		getData = function(self) return nil end,
	}
})

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

	self.getPacket = packet["get" .. proto .. "Packet"]
	self.minSize = ffi.sizeof(self.getPacket(test_packet()):getName())

	return setmetatable(self, Packet)
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

function Packet:prepare(error)
	if error:assertInvalidate(type(self.fillTbl.pktLength) == "number",
		"Packet field pktLength has to be set to a valid number.") then
		error:assertInvalidate(self.fillTbl.pktLength >= self.minSize,
			"Packet length is too short. Minimum size for %s is %d",
			self.proto, self.minSize)
	end

	if not self.prepared then
		self.dynvars:finalize()
		self.prepared = true
	end
end

return Packet
