local packet = require "packet"
local ffi    = require "ffi"

local dependencies = require "dependencies"

local Dynvars = require "flow.dynvars"

local Packet = {}
Packet.__index = Packet

ffi.cdef[[
	struct test_packet_t {};
]]

local test_packet = ffi.metatype("struct test_packet_t", {
	__index = {
		getLength = function() return 0 end,
		getData = function() return nil end,
	}
})

function Packet.new(proto, tbl, error)
	local self = {
		proto = proto,
		fillTbl = {}, depvars = {},
		dynvars = Dynvars.new()
	}

	for i,v in pairs(tbl) do
		local pkt, var = string.match(i, "^([%l%d]+)(%u[%l%d]*)$");

		if pkt then
			if type(v) == "function" then
				var = string.lower(var)
				v = self.dynvars:add(pkt, var, v).value
			elseif type(v) == "table" then
				local ft = error:assert(v[1] and dependencies[v[1]], "Invalid table passed to field '%s'.", i)
				table.insert(self.depvars, { field = i, dep = ft, tbl = v })
				v = nil
			end

			self.fillTbl[i] = v
		else
			error("Invalid packet field %q. Format is 'layerField' (e.g. ip4Dst).", i)
		end
	end

	self.getPacket = packet["get" .. proto .. "Packet"]
	local pkt = self.getPacket(test_packet())
	self.minSize = ffi.sizeof(pkt:getName())
	self.hasPayload = pcall(function() type(pkt.payload) end)

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

function Packet:prepare(final, error, flow)
	if error:assertInvalidate(type(self.fillTbl.pktLength) == "number",
		"Packet field pktLength has to be set to a valid number.") then
		error:assertInvalidate(self.fillTbl.pktLength >= self.minSize,
			"Packet length is too short. Minimum size for %s is %d",
			self.proto, self.minSize)
	end

	if final then
		if final ~= "debug" then
			for _,v in ipairs(self.depvars) do
				self.fillTbl[v.field] = v.dep.getValue(flow, v.tbl)
			end
		end

		self.dynvars:finalize()
	end
end

return Packet
